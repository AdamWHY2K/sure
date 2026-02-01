class AddAncestryToCategories < ActiveRecord::Migration[7.2]
  def change
    add_column :categories, :ancestry, :string
    add_index :categories, :ancestry
    add_column :categories, :ancestry_depth, :integer, default: 0

    # Migrate existing parent_id relationships to ancestry
    reversible do |dir|
      dir.up do
        # Reset column information to recognize new columns
        Category.reset_column_information

        # Build ancestry from existing parent_id relationships
        # The ancestry gem will handle UUID format with our primary_key_format config
        Category.build_ancestry_from_parent_ids!

        # Verify integrity
        Category.check_ancestry_integrity!
      end
    end

    # Keep parent_id for now to maintain backward compatibility during transition
    # The ancestry gem will auto-sync parent_id ↔ ancestry
  end
end
