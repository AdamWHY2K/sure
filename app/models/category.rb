class Category < ApplicationRecord
  # UUID v4 format without anchors for ancestry gem's composite pattern matching
  # Format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (32 hex digits with hyphens)
  UUID_PATTERN = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i

  # Add ancestry support for unlimited nesting with UUID primary keys
  # Note: No anchors (\A, \z) - ancestry gem adds its own anchors when building the full validation pattern
  # The ancestry gem provides virtual parent_id/parent methods calculated from ancestry column
  has_ancestry orphan_strategy: :restrict,
               primary_key_format: UUID_PATTERN

  has_many :transactions, dependent: :nullify, class_name: "Transaction"
  has_many :import_mappings, as: :mappable, dependent: :destroy, class_name: "Import::Mapping"

  belongs_to :family

  has_many :budget_categories, dependent: :destroy
  has_many :subcategories, class_name: "Category", foreign_key: :parent_id, dependent: :nullify
  belongs_to :parent, class_name: "Category", optional: true

  validates :name, :color, :lucide_icon, :family, presence: true
  validates :name, uniqueness: { scope: :family_id }

  validate :prevent_circular_ancestry
  validate :nested_category_matches_parent_classification

  # Keep parent_id column in sync with ancestry for SQL queries
  # Ancestry gem provides virtual parent_id from ancestry column, but SQL needs physical column
  before_save :sync_parent_id_from_ancestry

  before_save :inherit_color_from_parent

  scope :alphabetically, -> { order(:name) }
  scope :alphabetically_by_hierarchy, -> {
    left_joins(:parent)
      .order(Arel.sql("COALESCE(parents_categories.name, categories.name)"))
      .order(Arel.sql("parents_categories.name IS NOT NULL"))
      .order(:name)
  }
  scope :roots, -> { where(parent_id: nil) }
  scope :incomes, -> { where(classification: "income") }
  scope :expenses, -> { where(classification: "expense") }
  scope :leaves, -> { where.not(id: select(:parent_id).distinct) }
  scope :with_depth, ->(depth) { where(ancestry_depth: depth) }

  COLORS = %w[#e99537 #4da568 #6471eb #db5a54 #df4e92 #c44fe9 #eb5429 #61c9ea #805dee #6ad28a]

  UNCATEGORIZED_COLOR = "#737373"
  OTHER_INVESTMENTS_COLOR = "#e99537"
  TRANSFER_COLOR = "#444CE7"
  PAYMENT_COLOR = "#db5a54"
  TRADE_COLOR = "#e99537"

  # Category name keys for i18n
  UNCATEGORIZED_NAME_KEY = "models.category.uncategorized"
  OTHER_INVESTMENTS_NAME_KEY = "models.category.other_investments"
  INVESTMENT_CONTRIBUTIONS_NAME_KEY = "models.category.investment_contributions"

  class Group
    attr_reader :category, :subcategories

    delegate :name, :color, to: :category

    def self.for(categories)
      # Get root categories (depth 0)
      roots = categories.select { |c| c.ancestry_depth == 0 }

      roots.map do |root|
        # Get all descendants, not just immediate children
        descendants = categories.select { |c| c.ancestor_ids.include?(root.id) }
        new(root, descendants.sort_by { |c| [ c.ancestry_depth, c.name ] })
      end.sort_by { |group| group.category.name }
    end

    def initialize(category, subcategories = nil)
      @category = category
      @subcategories = subcategories || []
    end

    def subcategories_by_parent(parent_id)
      @subcategories.select { |sc| sc.parent_id == parent_id }
    end
  end

  class << self
    def icon_codes
      %w[
        ambulance apple award baby badge-dollar-sign banknote barcode bar-chart-3 bath
        battery bed-single beer bike bluetooth bone book book-open briefcase building bus
        cake calculator calendar-heart calendar-range camera car cat chart-line
        circle-dollar-sign circle-parking coffee coins compass cookie cooking-pot
        credit-card dices dog drama drill droplet drum dumbbell film flame flower flower-2
        fuel gamepad-2 gem gift glasses globe graduation-cap hammer hand-heart
        hand-helping heart-handshake handshake headphones heart heart-pulse home hotel
        house ice-cream-cone key landmark laptop leaf lightbulb luggage mail map-pin
        martini mic monitor moon music package palette party-popper paw-print pen pencil
        percent phone pie-chart piggy-bank pill pizza plane plug popcorn power printer
        puzzle receipt receipt-text ribbon scale scissors settings shield shield-plus
        shirt shopping-bag shopping-basket shopping-cart smartphone sparkles sprout
        stethoscope store sun tablet-smartphone tag target tent thermometer ticket train
        trees tree-palm trending-up trophy truck tv umbrella undo-2 unplug users utensils
        video wallet wallet-cards waves wifi wine wrench zap
      ]
    end

    def bootstrap!
      default_categories.each do |name, color, icon, classification|
        find_or_create_by!(name: name) do |category|
          category.color = color
          category.classification = classification
          category.lucide_icon = icon
        end
      end
    end

    def uncategorized
      new(
        name: I18n.t(UNCATEGORIZED_NAME_KEY),
        color: UNCATEGORIZED_COLOR,
        lucide_icon: "circle-dashed"
      )
    end

    def other_investments
      new(
        name: I18n.t(OTHER_INVESTMENTS_NAME_KEY),
        color: OTHER_INVESTMENTS_COLOR,
        lucide_icon: "trending-up"
      )
    end

    # Helper to get the localized name for uncategorized
    def uncategorized_name
      I18n.t(UNCATEGORIZED_NAME_KEY)
    end

    # Helper to get the localized name for other investments
    def other_investments_name
      I18n.t(OTHER_INVESTMENTS_NAME_KEY)
    end

    # Helper to get the localized name for investment contributions
    def investment_contributions_name
      I18n.t(INVESTMENT_CONTRIBUTIONS_NAME_KEY)
    end

    private
      def default_categories
        [
          [ "Income", "#22c55e", "circle-dollar-sign", "income" ],
          [ "Food & Drink", "#f97316", "utensils", "expense" ],
          [ "Groceries", "#407706", "shopping-bag", "expense" ],
          [ "Shopping", "#3b82f6", "shopping-cart", "expense" ],
          [ "Transportation", "#0ea5e9", "bus", "expense" ],
          [ "Travel", "#2563eb", "plane", "expense" ],
          [ "Entertainment", "#a855f7", "drama", "expense" ],
          [ "Healthcare", "#4da568", "pill", "expense" ],
          [ "Personal Care", "#14b8a6", "scissors", "expense" ],
          [ "Home Improvement", "#d97706", "hammer", "expense" ],
          [ "Mortgage / Rent", "#b45309", "home", "expense" ],
          [ "Utilities", "#eab308", "lightbulb", "expense" ],
          [ "Subscriptions", "#6366f1", "wifi", "expense" ],
          [ "Insurance", "#0284c7", "shield", "expense" ],
          [ "Sports & Fitness", "#10b981", "dumbbell", "expense" ],
          [ "Gifts & Donations", "#61c9ea", "hand-helping", "expense" ],
          [ "Taxes", "#dc2626", "landmark", "expense" ],
          [ "Loan Payments", "#e11d48", "credit-card", "expense" ],
          [ "Services", "#7c3aed", "briefcase", "expense" ],
          [ "Fees", "#6b7280", "receipt", "expense" ],
          [ "Savings & Investments", "#059669", "piggy-bank", "expense" ],
          [ investment_contributions_name, "#0d9488", "trending-up", "expense" ]
        ]
      end
  end

  def inherit_color_from_parent
    if subcategory?
      self.color = parent.color
    end
  end

  def replace_and_destroy!(replacement)
    transaction do
      # Update all transactions to use replacement category
      transactions.update_all category_id: replacement&.id

      # Move subcategories to replacement (or make them root if nil)
      # This prevents ancestry orphan_strategy: :restrict from blocking deletion
      # Use update_all for efficiency, manually update ancestry and parent_id
      if replacement
        children.update_all(
          ancestry: replacement.child_ancestry,
          ancestry_depth: replacement.depth + 1,
          parent_id: replacement.id
        )
      else
        # Make children root level
        children.update_all(
          ancestry: nil,
          ancestry_depth: 0,
          parent_id: nil
        )
      end

      destroy!
    end
  end

  def parent?
    subcategories.any?
  end

  def subcategory?
    parent.present?
  end

  def name_with_parent
    subcategory? ? "#{parent.name} > #{name}" : name
  end

  def hierarchy_path
    path.map(&:name).join(" > ")
  end

  def leaf?
    !has_children?
  end

  def all_descendants
    descendants # ancestry gem method
  end

  def root_ancestor
    root # ancestry gem method
  end

  # Predicate: is this the synthetic "Uncategorized" category?
  def uncategorized?
    !persisted? && name == I18n.t(UNCATEGORIZED_NAME_KEY)
  end

  # Predicate: is this the synthetic "Other Investments" category?
  def other_investments?
    !persisted? && name == I18n.t(OTHER_INVESTMENTS_NAME_KEY)
  end

  # Predicate: is this any synthetic (non-persisted) category?
  def synthetic?
    uncategorized? || other_investments?
  end

  private
    def prevent_circular_ancestry
      return unless parent_id_changed? && parent_id.present?

      # We can only check for cycles if this record has an ID (UUIDs are typically assigned before save)
      return if id.nil?

      # Use ancestry's ancestor traversal to detect cycles: the new parent cannot be self
      # and cannot have this category as one of its ancestors.
      if parent && (parent.id == id || parent.ancestor_ids.include?(id))
        errors.add(:parent, "cannot be a descendant of this category")
      end
    end

    def nested_category_matches_parent_classification
      if subcategory? && parent.classification != classification
        errors.add(:parent, "must have the same classification as its parent")
      end
    end

    # Sync the physical parent_id column with ancestry's virtual parent_id
    # This allows SQL queries to use c.parent_id without knowing ancestry's internal format
    def sync_parent_id_from_ancestry
      # Use write_attribute to avoid triggering ancestry's parent_id= setter
      write_attribute(:parent_id, parent_id)
    end

    def monetizable_currency
      family.currency
    end
end
