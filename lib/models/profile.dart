/// Mirrors the real `profiles` table.
///
/// `profiles` is intentionally minimal — it stores basic account info only:
///   id, full_name, email, phone_number, profile_image, created_at, updated_at
///
/// `profiles.id` is assumed to be the same UUID as the Supabase auth user
/// (`auth.uid()`), which is the standard Supabase "profiles" pattern and why
/// there is no separate `user_id` column here. All onboarding / financial
/// answers live in the `onboarding` table instead — see [OnboardingRecord].
class Profile {
  final String id;
  final String fullName;
  final String email;
  final String? phoneNumber;
  final String? profileImage;

  Profile({
    required this.id,
    required this.fullName,
    required this.email,
    this.phoneNumber,
    this.profileImage,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      fullName: map['full_name'] as String? ?? 'User',
      email: map['email'] as String? ?? '',
      phoneNumber: map['phone_number'] as String?,
      profileImage: map['profile_image'] as String?,
    );
  }

  /// Payload for insert/upsert into `profiles`. Deliberately excludes `id`
  /// (passed separately by the service, which knows the auth user id) and
  /// never includes any onboarding/financial field.
  Map<String, dynamic> toMap() {
    return {
      'full_name': fullName,
      'email': email,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (profileImage != null) 'profile_image': profileImage,
    };
  }
}
