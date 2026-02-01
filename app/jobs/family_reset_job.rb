class FamilyResetJob < ApplicationJob
  queue_as :low_priority

  def perform(family, load_sample_data_for_email: nil)
    # Delete all family data except users
    ActiveRecord::Base.transaction do
      # Delete accounts and related data
      family.accounts.destroy_all
      # Use delete_all for categories to bypass ancestry validations and destroy callbacks
      # during bulk deletion. This is acceptable here because FamilyResetJob performs a
      # full hard reset of all family-owned data, and no additional per-category cleanup
      # logic is required from callbacks in this context (destroy_all would fail due to
      # orphan_strategy: :restrict checking each record).
      family.categories.delete_all
      family.tags.destroy_all
      family.merchants.destroy_all
      family.plaid_items.destroy_all
      family.imports.destroy_all
      family.budgets.destroy_all
    end

    if load_sample_data_for_email.present?
      Demo::Generator.new.generate_new_user_data_for!(family.reload, email: load_sample_data_for_email)
    else
      family.sync_later
    end
  end
end
