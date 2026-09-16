# frozen_string_literal: true

module Date9ja
  module Import
    # The complete ISO 3166-1 country domain as name -> alpha-2, plus the
    # widely-used alternate English names, keyed by the same case/whitespace
    # normalization CountryMapping applies (lowercase, single-spaced). This is a
    # closed, exact table: it repairs no typos and infers no subdivisions. It
    # exists so a correctly-spelled country that simply did not appear in the
    # 2026-09-08 snapshot census still maps losslessly (audit blocker ledger
    # item 8) rather than being dropped.
    module IsoCountryAliases
      # rubocop:disable Layout/LineLength
      NAMES = {
        "afghanistan" => "AF", "aland islands" => "AX", "albania" => "AL", "algeria" => "DZ",
        "american samoa" => "AS", "andorra" => "AD", "angola" => "AO", "anguilla" => "AI",
        "antarctica" => "AQ", "antigua and barbuda" => "AG", "argentina" => "AR", "armenia" => "AM",
        "aruba" => "AW", "australia" => "AU", "austria" => "AT", "azerbaijan" => "AZ",
        "bahamas" => "BS", "the bahamas" => "BS", "bahrain" => "BH", "bangladesh" => "BD", "barbados" => "BB",
        "belarus" => "BY", "belgium" => "BE", "belize" => "BZ", "benin" => "BJ", "bermuda" => "BM",
        "bhutan" => "BT", "bolivia" => "BO", "bonaire" => "BQ", "bosnia and herzegovina" => "BA",
        "bosnia" => "BA", "botswana" => "BW", "bouvet island" => "BV", "brazil" => "BR",
        "british indian ocean territory" => "IO", "brunei" => "BN", "brunei darussalam" => "BN",
        "bulgaria" => "BG", "burkina faso" => "BF", "burma" => "MM", "burundi" => "BI",
        "cabo verde" => "CV", "cape verde" => "CV", "cambodia" => "KH", "cameroon" => "CM",
        "canada" => "CA", "cayman islands" => "KY", "central african republic" => "CF", "chad" => "TD",
        "chile" => "CL", "china" => "CN", "christmas island" => "CX", "cocos islands" => "CC",
        "colombia" => "CO", "comoros" => "KM", "congo" => "CG", "republic of the congo" => "CG",
        "democratic republic of the congo" => "CD", "dr congo" => "CD", "congo-kinshasa" => "CD",
        "congo-brazzaville" => "CG", "cook islands" => "CK", "costa rica" => "CR",
        "cote d ivoire" => "CI", "cote d'ivoire" => "CI", "ivory coast" => "CI", "croatia" => "HR",
        "cuba" => "CU", "curacao" => "CW", "cyprus" => "CY", "czechia" => "CZ", "czech republic" => "CZ",
        "denmark" => "DK", "djibouti" => "DJ", "dominica" => "DM", "dominican republic" => "DO",
        "ecuador" => "EC", "egypt" => "EG", "el salvador" => "SV", "equatorial guinea" => "GQ",
        "eritrea" => "ER", "estonia" => "EE", "eswatini" => "SZ", "swaziland" => "SZ",
        "ethiopia" => "ET", "falkland islands" => "FK", "faroe islands" => "FO", "fiji" => "FJ",
        "finland" => "FI", "france" => "FR", "french guiana" => "GF", "french polynesia" => "PF",
        "french southern territories" => "TF", "gabon" => "GA", "gambia" => "GM", "the gambia" => "GM",
        "georgia" => "GE", "germany" => "DE", "ghana" => "GH", "gibraltar" => "GI", "greece" => "GR",
        "greenland" => "GL", "grenada" => "GD", "guadeloupe" => "GP", "guam" => "GU", "guatemala" => "GT",
        "guernsey" => "GG", "guinea" => "GN", "guinea-bissau" => "GW", "guyana" => "GY", "haiti" => "HT",
        "heard island and mcdonald islands" => "HM", "holy see" => "VA", "vatican" => "VA",
        "vatican city" => "VA", "honduras" => "HN", "hong kong" => "HK", "hungary" => "HU",
        "iceland" => "IS", "india" => "IN", "indonesia" => "ID", "iran" => "IR", "iraq" => "IQ",
        "ireland" => "IE", "isle of man" => "IM", "israel" => "IL", "italy" => "IT", "jamaica" => "JM",
        "japan" => "JP", "jersey" => "JE", "jordan" => "JO", "kazakhstan" => "KZ", "kenya" => "KE",
        "kiribati" => "KI", "north korea" => "KP", "south korea" => "KR", "korea" => "KR",
        "republic of korea" => "KR", "kosovo" => "XK", "kuwait" => "KW", "kyrgyzstan" => "KG",
        "laos" => "LA", "latvia" => "LV", "lebanon" => "LB", "lesotho" => "LS", "liberia" => "LR",
        "libya" => "LY", "liechtenstein" => "LI", "lithuania" => "LT", "luxembourg" => "LU",
        "macao" => "MO", "macau" => "MO", "madagascar" => "MG", "malawi" => "MW", "malaysia" => "MY",
        "maldives" => "MV", "mali" => "ML", "malta" => "MT", "marshall islands" => "MH",
        "martinique" => "MQ", "mauritania" => "MR", "mauritius" => "MU", "mayotte" => "YT",
        "mexico" => "MX", "micronesia" => "FM", "moldova" => "MD", "monaco" => "MC", "mongolia" => "MN",
        "montenegro" => "ME", "montserrat" => "MS", "morocco" => "MA", "mozambique" => "MZ",
        "myanmar" => "MM", "namibia" => "NA", "nauru" => "NR", "nepal" => "NP", "netherlands" => "NL",
        "the netherlands" => "NL", "new caledonia" => "NC", "new zealand" => "NZ", "nicaragua" => "NI",
        "niger" => "NE", "nigeria" => "NG", "niue" => "NU", "norfolk island" => "NF",
        "north macedonia" => "MK", "macedonia" => "MK", "northern mariana islands" => "MP",
        "norway" => "NO", "oman" => "OM", "pakistan" => "PK", "palau" => "PW", "palestine" => "PS",
        "palestinian territory" => "PS", "panama" => "PA", "papua new guinea" => "PG", "paraguay" => "PY",
        "peru" => "PE", "philippines" => "PH", "the philippines" => "PH", "pitcairn" => "PN",
        "poland" => "PL", "portugal" => "PT", "puerto rico" => "PR", "qatar" => "QA", "reunion" => "RE",
        "romania" => "RO", "russia" => "RU", "russian federation" => "RU", "rwanda" => "RW",
        "saint barthelemy" => "BL", "saint helena" => "SH", "saint kitts and nevis" => "KN",
        "saint lucia" => "LC", "saint martin" => "MF", "saint pierre and miquelon" => "PM",
        "saint vincent and the grenadines" => "VC", "samoa" => "WS", "san marino" => "SM",
        "sao tome and principe" => "ST", "saudi arabia" => "SA", "senegal" => "SN", "serbia" => "RS",
        "seychelles" => "SC", "sierra leone" => "SL", "singapore" => "SG", "sint maarten" => "SX",
        "slovakia" => "SK", "slovenia" => "SI", "solomon islands" => "SB", "somalia" => "SO",
        "south africa" => "ZA", "south georgia and the south sandwich islands" => "GS",
        "south sudan" => "SS", "spain" => "ES", "sri lanka" => "LK", "sudan" => "SD", "suriname" => "SR",
        "svalbard and jan mayen" => "SJ", "sweden" => "SE", "switzerland" => "CH", "syria" => "SY",
        "taiwan" => "TW", "tajikistan" => "TJ", "tanzania" => "TZ", "thailand" => "TH",
        "timor-leste" => "TL", "east timor" => "TL", "togo" => "TG", "tokelau" => "TK", "tonga" => "TO",
        "trinidad and tobago" => "TT", "tunisia" => "TN", "turkey" => "TR", "turkiye" => "TR",
        "turkmenistan" => "TM", "turks and caicos islands" => "TC", "tuvalu" => "TV", "uganda" => "UG",
        "ukraine" => "UA", "united arab emirates" => "AE", "united kingdom" => "GB",
        "great britain" => "GB", "united states" => "US", "united states of america" => "US",
        "united states minor outlying islands" => "UM", "uruguay" => "UY", "uzbekistan" => "UZ",
        "vanuatu" => "VU", "venezuela" => "VE", "vietnam" => "VN", "viet nam" => "VN",
        "virgin islands british" => "VG", "virgin islands u s" => "VI", "wallis and futuna" => "WF",
        "western sahara" => "EH", "yemen" => "YE", "zambia" => "ZM", "zimbabwe" => "ZW"
      }.freeze
      # rubocop:enable Layout/LineLength
    end
  end
end
