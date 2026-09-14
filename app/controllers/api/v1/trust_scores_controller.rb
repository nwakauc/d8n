class Api::V1::TrustScoresController < ApplicationController
  before_action :authenticate_user!

  # A member's own derived trust score plus an explanation breakdown
  # (DECISIONS.md "score plus explanation", ADR 0025). Always recomputed from
  # the ledger — never a stored value that could drift.
  def show
    render json: {
      score: Trust::Ledger.score(user: Current.user, brand: Current.brand),
      breakdown: Trust::Ledger.breakdown(user: Current.user, brand: Current.brand).map { |entry| entry_payload(entry) }
    }
  end

  private

  def entry_payload(entry)
    {
      kind: entry.fetch(:kind),
      type: entry.fetch(:type),
      label: entry.fetch(:label),
      points: entry.fetch(:points),
      applies: entry.fetch(:applies),
      occurred_at: entry.fetch(:occurred_at)&.iso8601
    }
  end
end
