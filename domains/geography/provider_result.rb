module Geography
  # One normalized search result, independent of whichever provider produced
  # it. `place_id` is an existing, selectable Place — the same identifier
  # `PUT /api/v1/profile/place` already accepts — so search never needs its
  # own selection/write endpoint. No raw coordinates: callers only need enough
  # to display and disambiguate a choice.
  ProviderResult = Data.define(:place_id, :label, :area, :city, :region, :country_code, :kind)
end
