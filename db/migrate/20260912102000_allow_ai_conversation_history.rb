class AllowAiConversationHistory < ActiveRecord::Migration[8.1]
  def change
    remove_index :ai_conversations, name: "index_ai_conversations_active_member_assistant"
    add_index :ai_conversations, [ :brand_membership_id, :assistant_key, :last_message_at ],
      name: "index_ai_conversations_member_history"
  end
end
