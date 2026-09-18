require "rails_helper"

RSpec.describe Operator, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:buses).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:drivers).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:trips).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:stop_points).dependent(:nullify) }
  end

  describe "validations" do
    subject { build(:operator) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:slug) }
    it { is_expected.to validate_numericality_of(:rating).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(5) }
  end

  describe "#to_param" do
    it "puts the slug in URLs rather than the id" do
      expect(build(:operator, slug: "vrl-travels").to_param).to eq("vrl-travels")
    end
  end

  describe "database constraints" do
    it "refuses a rating above five" do
      operator = create(:operator)

      expect { described_class.where(id: operator.id).update_all(rating: 6) }
        .to raise_error(ActiveRecord::StatementInvalid, /operators_rating_in_range/)
    end
  end
end
