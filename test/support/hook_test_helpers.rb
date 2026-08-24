module HookTestHelpers
  # Builds a fully discoverable member: active/visible profile, adult birthdate,
  # and a preference open to every gender across a wide age band so any pair is
  # reciprocally eligible unless a test narrows it on purpose.
  def create_member(brand:, gender: "man", interested_in: %w[man woman non_binary], min_age: 18, max_age: 99)
    user = User.create!
    membership = BrandMembership.create!(brand:, user:)
    profile = Profile.create!(
      brand:, user:, brand_membership: membership, gender:,
      birthdate: 30.years.ago.to_date, status: :active, visibility: :visible
    )
    ProfilePreference.create!(brand:, user:, profile:, min_age:, max_age:, interested_in:)
    profile
  end

  def send_hook(sender:, brand:, target:, message: "You're seriously my vibe 🔥 Want to hook?")
    Hooks::SendHook.call(
      user: sender.user, brand:, target_public_id: target.public_id,
      message:, eligibility_policy: D8n::Platform::Brands::Hookus::ELIGIBILITY_POLICY
    )
  end
end
