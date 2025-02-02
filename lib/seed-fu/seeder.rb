require 'active_support/core_ext/hash/keys'

module SeedFu
  # Creates or updates seed records with data.
  #
  # It is not recommended to use this class directly. Instead, use `Model.seed`, and `Model.seed_once`,
  # where `Model` is your Active Record model.
  #
  # @see ActiveRecordExtension
  class Seeder
    # @param [ActiveRecord::Base] model_class The model to be seeded
    # @param [Array<Symbol>] constraints A list of attributes which identify a particular seed. If
    #   a record with these attributes already exists then it will be updated rather than created.
    # @param [Array<Hash>] data Each item in this array is a hash containing attributes for a
    #   particular record.
    # @param [Hash] options
    # @option options [Boolean] :quiet (SeedFu.quiet) If true, output will be silenced
    # @option options [Boolean] :insert_only (false) If true then existing records which match the
    #   constraints will not be updated, even if the seed data has changed
    def initialize(model_class, constraints, data, options = {})
      @model_class = model_class
      @constraints = constraints.to_a.empty? ? [:id] : constraints
      @data        = data.to_a || []
      @options     = options.symbolize_keys

      @options[:quiet] ||= SeedFu.quiet

      validate_constraints!
      validate_data!
    end

    # Insert/update the records as appropriate. Validation is skipped while saving.
    # @return [Array<ActiveRecord::Base>] The records which have been seeded
    def seed
      records = @model_class.transaction do
        @data.map { |record_data| seed_record(record_data.symbolize_keys) }
      end
      update_id_sequence
      records
    end

    private

      def validate_constraints!
        unknown_columns = @constraints.map(&:to_s) - @model_class.column_names
        unless unknown_columns.empty?
          raise(ArgumentError,
            "Your seed constraints contained unknown columns: #{column_list(unknown_columns)}. " +
            "Valid columns are: #{column_list(@model_class.column_names)}.")
        end
      end

      def validate_data!
        raise ArgumentError, "Seed data missing" if @data.empty?
      end

      def column_list(columns)
        '`' + columns.join("`, `") + '`'
      end

      def seed_record(data)
        record = find_or_initialize_record(data)
        return if @options[:insert_only] && !record.new_record?

        puts " - #{@model_class} #{data.inspect}" unless @options[:quiet]

        # Rails 3 or Rails 4 + rails/protected_attributes
        if record.class.respond_to?(:protected_attributes) && record.class.respond_to?(:accessible_attributes)
          record.assign_attributes(data,  :without_protection => true)
        # Rails 4 without rails/protected_attributes
        else
          record.assign_attributes(data)
        end
        record.save(:validate => false) || raise(ActiveRecord::RecordNotSaved, 'Record not saved!')
        record
      end

      def find_or_initialize_record(data)
        @model_class.where(constraint_conditions(data)).take ||
        @model_class.new
      end

      def constraint_conditions(data)
        Hash[@constraints.map { |c| [c, data[c.to_sym]] }]
      end

      def update_id_sequence
        if @model_class.connection.adapter_name == "PostgreSQL" or @model_class.connection.adapter_name == "PostGIS"
          return if @model_class.primary_key.nil? || @model_class.sequence_name.nil?

          max_seeded_id = @data.filter_map { |d| d["id"] }.max
          seq = @model_class.connection.execute(<<~SQL)
          SELECT last_value
          FROM #{@model_class.sequence_name}
          SQL
          last_seq_value = seq.first["last_value"]

          if max_seeded_id && last_seq_value < max_seeded_id
            # Update the sequence to start from the highest existing id
            @model_class.connection.reset_pk_sequence!(@model_class.table_name)
          else
            # The sequence is already higher than any of our seeded ids - better not touch it
          end
        end
      end
  end
end
