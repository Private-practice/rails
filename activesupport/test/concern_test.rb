# frozen_string_literal: true

require_relative "abstract_unit"
require "active_support/concern"

class ConcernTest < ActiveSupport::TestCase
  module Baz
    extend ActiveSupport::Concern

    class_methods do
      def baz
        "baz"
      end

      def included_ran=(value)
        @included_ran = value
      end

      def included_ran
        @included_ran
      end

      def prepended_ran=(value)
        @prepended_ran = value
      end

      def prepended_ran
        @prepended_ran
      end
    end

    included do
      self.included_ran = true
    end

    prepended do
      self.prepended_ran = true
    end

    def baz
      "baz"
    end
  end

  module Bar
    extend ActiveSupport::Concern

    include Baz

    module ClassMethods
      def baz
        "bar's baz + " + super
      end
    end

    def bar
      "bar"
    end

    def baz
      "bar+" + super
    end
  end

  module Foo
    extend ActiveSupport::Concern

    include Bar, Baz
  end

  module Qux
    module ClassMethods
    end
  end

  def setup
    @klass = Class.new
  end

  def test_module_is_included_normally
    @klass.include(Baz)
    assert_equal "baz", @klass.new.baz
    assert_includes @klass.included_modules, ConcernTest::Baz
  end

  def test_module_is_prepended_normally
    @klass.prepend(Baz)
    assert_equal "baz", @klass.new.baz
    assert_includes @klass.included_modules, ConcernTest::Baz
  end

  def test_class_methods_are_extended
    @klass.include(Baz)
    assert_equal "baz", @klass.baz
    assert_equal ConcernTest::Baz::ClassMethods, (class << @klass; included_modules; end)[0]
  end

  def test_class_methods_are_extended_when_prepended
    @klass.prepend(Baz)
    assert_equal "baz", @klass.baz
    assert_equal ConcernTest::Baz::ClassMethods, (class << @klass; included_modules; end)[0]
  end

  def test_class_methods_are_extended_only_on_expected_objects
    ::Object.include(Qux)
    Object.extend(Qux::ClassMethods)
    # module needs to be created after Qux is included in Object or bug won't
    # be triggered
    test_module = Module.new do
      extend ActiveSupport::Concern

      class_methods do
        def test
        end
      end
    end
    @klass.include test_module
    assert_not_respond_to Object, :test
    Qux.class_eval do
      remove_const :ClassMethods
    end
  end

  def test_included_block_is_ran
    @klass.include(Baz)
    assert_equal true, @klass.included_ran
  end

  def test_included_block_is_not_ran_when_prepended
    @klass.prepend(Baz)
    assert_nil @klass.included_ran
  end

  def test_prepended_block_is_ran
    @klass.prepend(Baz)
    assert_equal true, @klass.prepended_ran
  end

  def test_prepended_block_is_not_ran_when_included
    @klass.include(Baz)
    assert_nil @klass.prepended_ran
  end

  def test_modules_dependencies_are_met
    @klass.include(Bar)
    assert_equal "bar", @klass.new.bar
    assert_equal "bar+baz", @klass.new.baz
    assert_equal "bar's baz + baz", @klass.baz
    assert_includes @klass.included_modules, ConcernTest::Bar
  end

  def test_dependencies_with_multiple_modules
    @klass.include(Foo)
    assert_equal [ConcernTest::Foo, ConcernTest::Bar, ConcernTest::Baz], @klass.included_modules[0..2]
  end

  def test_dependencies_with_multiple_modules_when_prepended
    @klass.prepend(Foo)
    assert_equal [ConcernTest::Foo, ConcernTest::Bar, ConcernTest::Baz], @klass.included_modules[0..2]
  end

  def test_raise_on_multiple_included_calls
    assert_raises(ActiveSupport::Concern::MultipleIncludedBlocks) do
      Module.new do
        extend ActiveSupport::Concern

        included do
        end

        included do
        end
      end
    end
  end

  def test_raise_on_multiple_prepended_calls
    assert_raises(ActiveSupport::Concern::MultiplePrependBlocks) do
      Module.new do
        extend ActiveSupport::Concern

        prepended do
        end

        prepended do
        end
      end
    end
  end

  def test_no_raise_on_same_included_or_prepended_call
    assert_nothing_raised do
      2.times do
        load File.expand_path("../fixtures/concern/some_concern.rb", __FILE__)
      end
    end
  end
end
