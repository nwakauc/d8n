class AddLanguageToAiConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_conversations, :language, :string, null: false, default: "english"
  end
end
