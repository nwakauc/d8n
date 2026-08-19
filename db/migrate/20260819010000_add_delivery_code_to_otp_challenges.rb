class AddDeliveryCodeToOtpChallenges < ActiveRecord::Migration[8.1]
  # Ciphertext column for the one-time code so a Solid Queue worker can deliver it
  # after commit WITHOUT the plaintext ever entering job arguments, logs, or
  # SecurityEvent metadata. At rest this holds Active Record Encryption ciphertext,
  # never the digits; it is cleared to NULL the moment delivery succeeds (or is
  # permanently abandoned). `code_digest` remains the authoritative verifier.
  def change
    add_column :otp_challenges, :delivery_code, :text
  end
end
