if ENV["COVERAGE"] == "true"
  require "simplecov"
  SimpleCov.start "rails" do
    enable_coverage :branch
  end
end

require_relative "../config/environment"

ENV["RAILS_ENV"] ||= "test"

# Set Plaid to sandbox mode for tests
ENV["PLAID_ENV"] = "sandbox"
ENV["PLAID_CLIENT_ID"] ||= "test_client_id"
ENV["PLAID_SECRET"] ||= "test_secret"

# Fixes Segfaults on M1 Macs when running tests in parallel (temporary workaround)
ENV["PGGSSENCMODE"] = "disable"

require "rails/test_help"
require "minitest/mock"
require "minitest/autorun"
require "mocha/minitest"
require "aasm/minitest"
require "webmock/minitest"

VCR.configure do |config|
  config.cassette_library_dir = "test/vcr_cassettes"
  config.hook_into :webmock
  config.ignore_localhost = true
  config.default_cassette_options = { erb: true }
  config.filter_sensitive_data("<OPENAI_ACCESS_TOKEN>") { ENV["OPENAI_ACCESS_TOKEN"] }
  config.filter_sensitive_data("<OPENAI_ORGANIZATION_ID>") { ENV["OPENAI_ORGANIZATION_ID"] }
  config.filter_sensitive_data("<STRIPE_SECRET_KEY>") { ENV["STRIPE_SECRET_KEY"] }
  config.filter_sensitive_data("<STRIPE_WEBHOOK_SECRET>") { ENV["STRIPE_WEBHOOK_SECRET"] }
  config.filter_sensitive_data("<PLAID_CLIENT_ID>") { ENV["PLAID_CLIENT_ID"] }
  config.filter_sensitive_data("<PLAID_SECRET>") { ENV["PLAID_SECRET"] }
end

# Configure OmniAuth for testing
OmniAuth.config.test_mode = true
# Allow both GET and POST for OIDC callbacks in tests
OmniAuth.config.allowed_request_methods = [ :get, :post ]

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors) unless ENV["DISABLE_PARALLELIZATION"] == "true"

    # https://github.com/simplecov-ruby/simplecov/issues/718#issuecomment-538201587
    if ENV["COVERAGE"] == "true"
      parallelize_setup do |worker|
        SimpleCov.command_name "#{SimpleCov.command_name}-#{worker}"
      end

      parallelize_teardown do |worker|
        SimpleCov.result
      end
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Rebuild ancestry from parent_ids after fixtures load
    # In parallel mode: runs once per worker via parallelize_setup
    # In single-process mode: runs via setup_fixtures override
    parallelize_setup do |worker|
      rebuild_category_ancestry
    end

    def self.rebuild_category_ancestry
      return unless defined?(Category) && Category.table_exists?
      Category.build_ancestry_from_parent_ids!
      # Sync physical parent_id column from ancestry
      Category.find_each { |c| c.update_column(:parent_id, c.parent_id) }
    rescue ActiveRecord::StatementInvalid
      # Ignore if table doesn't exist yet
    end

    def setup_fixtures(*args)
      super
      # Only rebuild in single-process mode (parallel mode uses parallelize_setup)
      workers = self.class.respond_to?(:parallelize_workers) ? self.class.parallelize_workers : nil
      if !workers || workers <= 1
        self.class.rebuild_category_ancestry
      end
    end

    # Add more helper methods to be used by all tests here...
    def sign_in(user)
      post sessions_path, params: { email: user.email, password: user_password_test }
    end

    def with_env_overrides(overrides = {}, &block)
      ClimateControl.modify(**overrides, &block)
    end

    def with_self_hosting
      Rails.configuration.stubs(:app_mode).returns("self_hosted".inquiry)
      yield
    end

    def user_password_test
      "maybetestpassword817983172"
    end

    # Ensures the Investment Contributions category exists for a family
    # Used in transfer tests where this bootstrapped category is required
    def ensure_investment_contributions_category(family)
      family.categories.find_or_create_by!(name: Category.investment_contributions_name) do |c|
        c.color = "#0d9488"
        c.lucide_icon = "trending-up"
        c.classification = "expense"
      end
    end
  end
end

Dir[Rails.root.join("test", "interfaces", "**", "*.rb")].each { |f| require f }
