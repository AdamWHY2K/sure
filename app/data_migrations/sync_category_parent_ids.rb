# frozen_string_literal: true

# Sync physical parent_id column from ancestry's virtual parent_id
# After adding ancestry gem, parent_id needs to be kept in sync for SQL queries
class SyncCategoryParentIds < DataMigration
  def up
    Category.find_each do |category|
      # Use update_column to skip callbacks and validations
      category.update_column(:parent_id, category.parent_id)
    end
  end
end
