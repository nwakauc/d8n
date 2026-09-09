require "test_helper"

module Profiles
  class Date9jaOnboardingParityTest < ActionDispatch::IntegrationTest
    COMPATIBILITY_OPTIONS = {
      "family_involvement" => %w[must_approve blessing_matters later_when_serious my_decision_alone],
      "faith_practice" => %w[central_daily practice_regularly practice_flexibly not_a_factor],
      "money_providing" => %w[both_one_purse joint_and_personal split_bills earner_carries_more],
      "settlement" => %w[nigeria_staying_returning diaspora_visiting_often open_to_relocate abroad_home_eventually],
      "children" => %w[want_soon want_no_rush open_either_way dont_want],
      "conflict" => %w[talk_now cool_off_first trusted_mediator avoid_until_passes]
    }.freeze

    setup do
      @brand = Brand.create!(slug: "date9ja", name: "Date9ja")
      Date9jaProfileCatalog.install!(brand: @brand)
      BrandDomain.create!(brand: @brand, host: "date9ja.test")
      @user = User.create!(first_name: "Ada", last_name: "Nwosu")
      @membership = BrandMembership.create!(brand: @brand, user: @user)
      @token, = Session.issue!(brand: @brand, user: @user)
      host! "date9ja.test"
    end

    test "configuration exposes Date9ja cultural and compatibility contract" do
      configuration = Configuration.call(brand: @brand)
      fields = configuration.fetch(:profile_fields).map { |field| field.fetch(:key) }
      assert_includes fields, "is_nigerian"
      assert_includes fields, "state_of_origin"
      assert_includes fields, "nationality"
      assert_equal 10, configuration.fetch(:profile_fields).find { |field| field.fetch(:key) == "bio" }
        .fetch(:minimum_length)
      groups = configuration.fetch(:option_groups).index_by { |group| group.fetch(:key) }
      %w[religion religion_importance tribe genotype].each do |key|
        assert_includes groups, key
        assert_equal "owner_only", groups.fetch(key).fetch(:visibility)
      end
      COMPATIBILITY_OPTIONS.each do |key, options|
        assert_equal options, groups.fetch(key).fetch(:options).pluck(:code)
        assert_equal "owner_only", groups.fetch(key).fetch(:visibility)
      end
      assert_equal [ "state_of_origin" ], configuration.dig(:conditional_requirements, :profile_fields).first.fetch("fields")
    end

    test "owner can write and read sensitive and compatibility option answers" do
      patch "/api/v1/profile", headers: bearer, params: {
        display_name: "Ada", bio: "A real biography", is_nigerian: true, state_of_origin: "Enugu"
      }
      assert_response :success

      selections = {
        religion: [ "christian" ], religion_importance: [ "very_important" ],
        tribe: [ "igbo" ], genotype: [ "aa" ]
      }.merge(COMPATIBILITY_OPTIONS.transform_values { |codes| [ codes.first ] })
      patch "/api/v1/profile/options", headers: bearer, params: { selections: }
      assert_response :success
      assert_equal selections.deep_stringify_keys, JSON.parse(response.body).dig("profile", "options").slice(*selections.keys.map(&:to_s))

      get "/api/v1/profile", headers: bearer
      assert_response :success
      assert_equal selections.deep_stringify_keys, JSON.parse(response.body).dig("profile", "options").slice(*selections.keys.map(&:to_s))

      persisted = Profile.find_by!(brand: @brand, user: @user).profile_option_selections.kept
        .includes(:profile_option, :profile_option_group)
        .to_h { |selection| [ selection.profile_option_group.key, selection.profile_option.code ] }
      selections.each { |key, codes| assert_equal codes.first, persisted.fetch(key.to_s) }
    end

    test "owner-only answers stay out of public discovery match detail and conversation payloads" do
      profile = create_profile(user: @user, membership: @membership, display_name: "Ada", gender: "woman")
      OptionSelections.replace!(profile:, selections: {
        religion: [ "christian" ], tribe: [ "igbo" ], genotype: [ "aa" ],
        family_involvement: [ "must_approve" ], faith_practice: [ "central_daily" ],
        money_providing: [ "both_one_purse" ], settlement: [ "open_to_relocate" ],
        children: [ "want_soon" ], conflict: [ "talk_now" ]
      })
      viewer_user = User.create!
      viewer = create_profile(
        user: viewer_user,
        membership: BrandMembership.create!(brand: @brand, user: viewer_user),
        display_name: "Ben",
        gender: "man"
      )
      first_id, second_id = Match.canonical_pair(viewer.id, profile.id)
      match = Match.create!(brand: @brand, profile_a_id: first_id, profile_b_id: second_id)
      conversation = Conversation.create!(brand: @brand, match:)
      [ viewer, profile ].each do |participant|
        conversation.conversation_participants.create!(
          brand: @brand, profile: participant, user: participant.user
        )
      end

      payloads = [
        PublicSerializer.call(profile:),
        Matching::CandidateSerializer.call(
          profile:, strategy: Matching::Strategies::Date9jaContract, compatibility: {}
        ),
        DetailSerializer.call(profile:, viewer:),
        Messaging::ConversationSerializer.call(conversation:, viewer:)
      ]
      payloads.each do |payload|
        profile_payload = payload[:profile] || payload
        sensitive = profile_payload.fetch(:options, {}).keys.map(&:to_s) &
          (%w[religion religion_importance tribe genotype] + COMPATIBILITY_OPTIONS.keys)
        assert_empty sensitive
      end
    end

    test "Nigerian and non-Nigerian completion branches require only their intended cultural fields" do
      nigerian = create_profile(user: @user, membership: @membership, is_nigerian: true)
      missing = Completion.call(profile: nigerian).missing
      assert_includes missing, :state_of_origin
      assert_includes missing, :"options.tribe"
      refute_includes missing, :nationality

      nigerian.update!(state_of_origin: "Enugu")
      OptionSelections.replace!(profile: nigerian, selections: { tribe: [ "igbo" ] })
      missing = Completion.call(profile: nigerian).missing
      refute_includes missing, :state_of_origin
      refute_includes missing, :"options.tribe"
      refute_includes missing, :nationality

      other_user = User.create!(first_name: "Zola", last_name: "Dlamini")
      non_nigerian = create_profile(
        user: other_user,
        membership: BrandMembership.create!(brand: @brand, user: other_user),
        is_nigerian: false
      )
      missing = Completion.call(profile: non_nigerian).missing
      assert_includes missing, :nationality
      refute_includes missing, :state_of_origin
      refute_includes missing, :"options.tribe"

      non_nigerian.update!(nationality: "ZA")
      refute_includes Completion.call(profile: non_nigerian).missing, :nationality
    end

    test "Date9ja biography minimum is enforced at nine characters and accepts ten" do
      profile = Profile.new(
        brand: @brand, user: @user, brand_membership: @membership, bio: "123456789"
      )
      assert_not profile.valid?
      assert_includes profile.errors[:bio], "is too short (minimum is 10 characters)"

      profile.bio = "1234567890"
      assert profile.valid?, profile.errors.full_messages.to_sentence
    end

    test "configuration cannot invoke arbitrary profile methods through minimums or conditions" do
      malicious_minimum = @brand.profile_requirements.deep_dup.merge(
        "minimum_lengths" => { "destroy!" => 1 }
      )
      @brand.profile_requirements = malicious_minimum
      assert_not @brand.valid?
      assert_includes @brand.errors[:profile_requirements], "contains unsupported minimum lengths"

      malicious_condition = Date9jaProfileCatalog::REQUIREMENTS.deep_dup
      malicious_condition[:conditional_profile_fields] = [
        { "if" => { "destroy!" => true }, "fields" => [ "state_of_origin" ] }
      ]
      @brand.profile_requirements = malicious_condition
      assert_not @brand.valid?
      assert_includes @brand.errors[:profile_requirements], "contains unsupported conditional requirements"
      assert Profile.exists?(create_profile(user: @user, membership: @membership).id)
    end

    test "DateZA and HookUs do not inherit Date9ja cultural fields or option groups" do
      dateza = Brand.create!(slug: "dateza-parity", name: "DateZA")
      DatezaProfileCatalog.install!(brand: dateza)
      hookus = Brand.create!(slug: "hookus-parity", name: "HookUs")
      HookusProfileCatalog.install!(brand: hookus)
      sensitive_groups = %w[tribe genotype family_involvement faith_practice money_providing settlement children conflict]

      [ dateza, hookus ].each do |brand|
        assert_empty brand.profile_option_groups.kept.where(key: sensitive_groups)
        requirements = brand.profile_completion_requirements
        refute_includes requirements.fetch("profile_fields"), "is_nigerian"
        assert_empty Array(requirements["conditional_profile_fields"])
        assert_empty Array(requirements["conditional_option_groups"])
      end
    end

    private

    def bearer
      { "Authorization" => "Bearer #{@token}" }
    end

    def create_profile(user:, membership:, display_name: "Member", gender: nil, is_nigerian: nil)
      Profile.create!(
        brand: @brand, user:, brand_membership: membership, display_name:,
        bio: "A real biography", birthdate: 30.years.ago.to_date, gender:,
        country_code: "NG", city: "Lagos", is_nigerian:,
        status: :active, visibility: :visible
      )
    end
  end
end
