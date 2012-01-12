require "cases/helper"

module ActiveRecord
  class Migration
    class ColumnAttributesTest < ActiveRecord::TestCase
      self.use_transactional_fixtures = false

      class TestModel < ActiveRecord::Base
        self.table_name = 'test_models'
      end

      attr_reader :connection, :table_name

      def setup
        super
        @connection = ActiveRecord::Base.connection
        connection.create_table :test_models do |t|
          t.timestamps
        end

        TestModel.reset_column_information
      end

      def teardown
        super
        connection.drop_table :test_models rescue nil
      end

      # We specifically do a manual INSERT here, and then test only the SELECT
      # functionality. This allows us to more easily catch INSERT being broken,
      # but SELECT actually working fine.
      def test_native_decimal_insert_manual_vs_automatic
        correct_value = '0012345678901234567890.0123456789'.to_d

        connection.add_column "test_models", "wealth", :decimal, :precision => '30', :scale => '10'

        # Do a manual insertion
        if current_adapter?(:OracleAdapter)
          connection.execute "insert into test_models (id, wealth, created_at, updated_at) values (people_seq.nextval, 12345678901234567890.0123456789, sysdate, sysdate)"
        elsif current_adapter?(:OpenBaseAdapter) || (current_adapter?(:MysqlAdapter) && Mysql.client_version < 50003) #before mysql 5.0.3 decimals stored as strings
          connection.execute "insert into test_models (wealth, created_at, updated_at) values ('12345678901234567890.0123456789', 0, 0)"
        elsif current_adapter?(:PostgreSQLAdapter)
          connection.execute "insert into test_models (wealth, created_at, updated_at) values (12345678901234567890.0123456789, now(), now())"
        else
          connection.execute "insert into test_models (wealth, created_at, updated_at) values (12345678901234567890.0123456789, 0, 0)"
        end

        # SELECT
        row = TestModel.find(:first)
        assert_kind_of BigDecimal, row.wealth

        # If this assert fails, that means the SELECT is broken!
        unless current_adapter?(:SQLite3Adapter)
          assert_equal correct_value, row.wealth
        end

        # Reset to old state
        TestModel.delete_all

        # Now use the Rails insertion
        TestModel.create :wealth => BigDecimal.new("12345678901234567890.0123456789")

        # SELECT
        row = TestModel.find(:first)
        assert_kind_of BigDecimal, row.wealth

        # If these asserts fail, that means the INSERT (create function, or cast to SQL) is broken!
        unless current_adapter?(:SQLite3Adapter)
          assert_equal correct_value, row.wealth
        end
      end

      def test_add_column_with_precision_and_scale
        connection.add_column 'test_models', 'wealth', :decimal, :precision => 9, :scale => 7

        wealth_column = TestModel.columns_hash['wealth']
        assert_equal 9, wealth_column.precision
        assert_equal 7, wealth_column.scale
      end

      def test_change_column_preserve_other_column_precision_and_scale
        skip "only on sqlite3" unless current_adapter?(:SQLite3Adapter)

        connection.add_column 'test_models', 'last_name', :string
        connection.add_column 'test_models', 'wealth', :decimal, :precision => 9, :scale => 7

        wealth_column = TestModel.columns_hash['wealth']
        assert_equal 9, wealth_column.precision
        assert_equal 7, wealth_column.scale

        connection.change_column 'test_models', 'last_name', :string, :null => false
        TestModel.reset_column_information

        wealth_column = TestModel.columns_hash['wealth']
        assert_equal 9, wealth_column.precision
        assert_equal 7, wealth_column.scale
      end

      def test_native_types
        add_column "test_models", "first_name", :string
        add_column "test_models", "last_name", :string
        add_column "test_models", "bio", :text
        add_column "test_models", "age", :integer
        add_column "test_models", "height", :float
        add_column "test_models", "wealth", :decimal, :precision => '30', :scale => '10'
        add_column "test_models", "birthday", :datetime
        add_column "test_models", "favorite_day", :date
        add_column "test_models", "moment_of_truth", :datetime
        add_column "test_models", "male", :boolean

        TestModel.create :first_name => 'bob', :last_name => 'bobsen',
          :bio => "I was born ....", :age => 18, :height => 1.78,
          :wealth => BigDecimal.new("12345678901234567890.0123456789"),
          :birthday => 18.years.ago, :favorite_day => 10.days.ago,
          :moment_of_truth => "1782-10-10 21:40:18", :male => true

        bob = TestModel.find(:first)
        assert_equal 'bob', bob.first_name
        assert_equal 'bobsen', bob.last_name
        assert_equal "I was born ....", bob.bio
        assert_equal 18, bob.age

        # Test for 30 significant digits (beyond the 16 of float), 10 of them
        # after the decimal place.

        unless current_adapter?(:SQLite3Adapter)
          assert_equal BigDecimal.new("0012345678901234567890.0123456789"), bob.wealth
        end

        assert_equal true, bob.male?

        assert_equal String, bob.first_name.class
        assert_equal String, bob.last_name.class
        assert_equal String, bob.bio.class
        assert_equal Fixnum, bob.age.class
        assert_equal Time, bob.birthday.class

        if current_adapter?(:OracleAdapter, :SybaseAdapter)
          # Sybase, and Oracle don't differentiate between date/time
          assert_equal Time, bob.favorite_day.class
        else
          assert_equal Date, bob.favorite_day.class
        end

        # Oracle adapter stores Time or DateTime with timezone value already in _before_type_cast column
        # therefore no timezone change is done afterwards when default timezone is changed
        unless current_adapter?(:OracleAdapter)
          # Test DateTime column and defaults, including timezone.
          # FIXME: moment of truth may be Time on 64-bit platforms.
          if bob.moment_of_truth.is_a?(DateTime)

            with_env_tz 'US/Eastern' do
              bob.reload
              assert_equal DateTime.local_offset, bob.moment_of_truth.offset
              assert_not_equal 0, bob.moment_of_truth.offset
              assert_not_equal "Z", bob.moment_of_truth.zone
              # US/Eastern is -5 hours from GMT
              assert_equal Rational(-5, 24), bob.moment_of_truth.offset
              assert_match(/\A-05:?00\Z/, bob.moment_of_truth.zone) #ruby 1.8.6 uses HH:MM, prior versions use HHMM
              assert_equal DateTime::ITALY, bob.moment_of_truth.start
            end
          end
        end

        assert_instance_of TrueClass, bob.male?
        assert_kind_of BigDecimal, bob.wealth
      end

      def add_column(*args)
        connection.add_column(*args)
      end
    end
  end
end
