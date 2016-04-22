require 'rails_helper'

RSpec.describe People2publication, :type => :model do
  describe "new" do
      it { should validate_presence_of(:publication_version) }
      it { should validate_presence_of(:person) }
      it { should validate_presence_of(:position) }
      it { should validate_uniqueness_of(:position).scoped_to(:publication_version_id) }
  end
end
