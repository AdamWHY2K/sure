require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  def setup
    @family = families(:dylan_family)
  end

  test "replacing and destroying" do
    transactions = categories(:food_and_drink).transactions.to_a

    categories(:food_and_drink).replace_and_destroy!(categories(:income))

    assert_equal categories(:income), transactions.map { |t| t.reload.category }.uniq.first
  end

  test "replacing with nil should nullify the category" do
    transactions = categories(:food_and_drink).transactions.to_a

    categories(:food_and_drink).replace_and_destroy!(nil)

    assert_nil transactions.map { |t| t.reload.category }.uniq.first
  end

  test "allows unlimited nesting depth" do
    # Verify 4-level deep hierarchy works (was previously limited to 2 levels)
    assert_equal 0, categories(:level_1).depth
    assert_nil categories(:level_1).parent

    assert_equal 1, categories(:level_2).depth
    assert_equal categories(:level_1), categories(:level_2).parent

    assert_equal 2, categories(:level_3).depth
    assert_equal categories(:level_2), categories(:level_3).parent
    assert_equal categories(:level_1), categories(:level_3).root

    assert_equal 3, categories(:level_4).depth
    assert_equal categories(:level_3), categories(:level_4).parent
    assert_equal categories(:level_1), categories(:level_4).root
  end
end
