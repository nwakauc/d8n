class MakeMessageBodyOptional < ActiveRecord::Migration[8.1]
  # Chat media (D8N Chat Media) lets a message carry attachments with no text at
  # all. The body-or-attachment invariant is enforced in the model layer
  # (Message#must_have_body_or_attachment), not a DB check constraint, because it
  # depends on the sibling message_attachments table.
  def change
    change_column_null :messages, :body, true
  end
end
