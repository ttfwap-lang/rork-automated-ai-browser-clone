import Foundation

/// One kind of fact the dossier can hold.
///
/// This list is deliberately finite and deliberately excludes every secret: no
/// password, no card number, no security code, no national insurance or social
/// security number. The dossier physically cannot hold one, so no amount of
/// clever page markup can talk the agent into typing one — the guarantee holds
/// by construction rather than by policy.
nonisolated enum DossierFieldKind: String, CaseIterable, Identifiable, Codable, Sendable {
    // Who you are
    case fullName
    case firstName
    case lastName
    case pronouns
    case dateOfBirth

    // How to reach you
    case email
    case phone

    // Where you live
    case addressLine1
    case addressLine2
    case city
    case region
    case postcode
    case country

    // Work
    case currentTitle
    case currentEmployer
    case yearsExperience
    case summary

    // Education
    case highestDegree
    case fieldOfStudy
    case school
    case graduationYear

    // Links
    case linkedIn
    case portfolio
    case github

    // The extras applications ask for
    case noticePeriod
    case salaryExpectation
    case earliestStartDate
    case workAuthorisation
    case needsSponsorship
    case willingToRelocate
    case preferredLocation
    case howDidYouHear
    case referredBy

    var id: String { rawValue }

    var category: DossierCategory {
        switch self {
        case .fullName, .firstName, .lastName, .pronouns, .dateOfBirth: .identity
        case .email, .phone: .contact
        case .addressLine1, .addressLine2, .city, .region, .postcode, .country: .address
        case .currentTitle, .currentEmployer, .yearsExperience, .summary: .work
        case .highestDegree, .fieldOfStudy, .school, .graduationYear: .education
        case .linkedIn, .portfolio, .github: .links
        case .noticePeriod, .salaryExpectation, .earliestStartDate, .workAuthorisation,
             .needsSponsorship, .willingToRelocate, .preferredLocation, .howDidYouHear, .referredBy: .extras
        }
    }

    /// The label shown in the editor.
    var label: String {
        switch self {
        case .fullName: "Full name"
        case .firstName: "First name"
        case .lastName: "Last name"
        case .pronouns: "Pronouns"
        case .dateOfBirth: "Date of birth"
        case .email: "Email"
        case .phone: "Phone"
        case .addressLine1: "Street address"
        case .addressLine2: "Apartment, suite, etc."
        case .city: "City"
        case .region: "State / county"
        case .postcode: "Postcode / ZIP"
        case .country: "Country"
        case .currentTitle: "Current job title"
        case .currentEmployer: "Current employer"
        case .yearsExperience: "Years of experience"
        case .summary: "Short professional summary"
        case .highestDegree: "Highest degree"
        case .fieldOfStudy: "Field of study"
        case .school: "School / university"
        case .graduationYear: "Graduation year"
        case .linkedIn: "LinkedIn"
        case .portfolio: "Portfolio / website"
        case .github: "GitHub"
        case .noticePeriod: "Notice period"
        case .salaryExpectation: "Salary expectation"
        case .earliestStartDate: "Earliest start date"
        case .workAuthorisation: "Right to work"
        case .needsSponsorship: "Needs visa sponsorship"
        case .willingToRelocate: "Willing to relocate"
        case .preferredLocation: "Preferred location"
        case .howDidYouHear: "How you heard about the role"
        case .referredBy: "Referred by"
        }
    }

    /// Shown in the empty text field, so it is obvious what shape the answer takes.
    var placeholder: String {
        switch self {
        case .fullName: "Alex Morgan"
        case .firstName: "Alex"
        case .lastName: "Morgan"
        case .pronouns: "she/her"
        case .dateOfBirth: "1994-06-12"
        case .email: "alex@example.com"
        case .phone: "+44 7700 900123"
        case .addressLine1: "18 Kingsland Road"
        case .addressLine2: "Flat 4"
        case .city: "London"
        case .region: "Greater London"
        case .postcode: "E2 8AA"
        case .country: "United Kingdom"
        case .currentTitle: "Senior Product Designer"
        case .currentEmployer: "Northwind Studio"
        case .yearsExperience: "7"
        case .summary: "One or two sentences about your work"
        case .highestDegree: "BSc"
        case .fieldOfStudy: "Computer Science"
        case .school: "University of Bristol"
        case .graduationYear: "2016"
        case .linkedIn: "https://linkedin.com/in/…"
        case .portfolio: "https://…"
        case .github: "https://github.com/…"
        case .noticePeriod: "1 month"
        case .salaryExpectation: "65000"
        case .earliestStartDate: "2026-09-01"
        case .workAuthorisation: "Authorised to work in the UK"
        case .needsSponsorship: "No"
        case .willingToRelocate: "Yes"
        case .preferredLocation: "London or remote"
        case .howDidYouHear: "Company website"
        case .referredBy: "—"
        }
    }

    /// True for the one fact long enough to need a multi-line editor.
    var isLongForm: Bool { self == .summary }

    /// The HTML `autocomplete` tokens that mean exactly this fact.
    ///
    /// This is the machine-readable half of the matching: a field that declares
    /// its own purpose needs no guessing, no keywords and no model — which is why
    /// most of a fifty-field application resolves for nothing.
    var declaredTokens: [String] {
        switch self {
        case .fullName: ["name"]
        case .firstName: ["given-name", "givenname", "fname", "first-name"]
        case .lastName: ["family-name", "familyname", "lname", "last-name", "surname"]
        case .pronouns: []
        case .dateOfBirth: ["bday", "birthday"]
        case .email: ["email", "username"]
        case .phone: ["tel", "tel-national", "phone", "telephone", "mobile"]
        case .addressLine1: ["address-line1", "street-address", "address-line-1", "addressline1"]
        case .addressLine2: ["address-line2", "address-line-2", "addressline2"]
        case .city: ["address-level2", "city", "locality"]
        case .region: ["address-level1", "region", "state", "province"]
        case .postcode: ["postal-code", "postalcode", "zip", "zipcode", "zip-code"]
        case .country: ["country", "country-name"]
        case .currentTitle: ["organization-title", "job-title", "jobtitle"]
        case .currentEmployer: ["organization", "company"]
        case .yearsExperience: []
        case .summary: []
        case .highestDegree: []
        case .fieldOfStudy: []
        case .school: []
        case .graduationYear: []
        case .linkedIn: ["linkedin"]
        case .portfolio: ["url", "website", "homepage"]
        case .github: ["github"]
        case .noticePeriod: []
        case .salaryExpectation: []
        case .earliestStartDate: []
        case .workAuthorisation: []
        case .needsSponsorship: []
        case .willingToRelocate: []
        case .preferredLocation: []
        case .howDidYouHear: []
        case .referredBy: []
        }
    }

    /// Phrases that identify this fact from a field's own visible words, longest
    /// and most specific first. Matched on word boundaries, never as loose
    /// substrings, so "state" cannot be found inside "estate".
    var phrases: [String] {
        switch self {
        case .fullName: ["full name", "your name", "legal name", "name"]
        case .firstName: ["first name", "given name", "forename", "first"]
        case .lastName: ["last name", "family name", "surname", "last"]
        case .pronouns: ["pronouns", "preferred pronouns"]
        case .dateOfBirth: ["date of birth", "birth date", "birthdate", "dob"]
        case .email: ["email address", "e-mail address", "email", "e-mail"]
        case .phone: ["phone number", "mobile number", "telephone", "phone", "mobile", "cell"]
        case .addressLine1: ["street address", "address line 1", "address line one", "address 1", "street", "address"]
        case .addressLine2: ["address line 2", "address line two", "address 2", "apartment", "apt", "suite", "unit"]
        case .city: ["city", "town", "locality"]
        case .region: ["state or province", "state / province", "state", "province", "county", "region"]
        case .postcode: ["postal code", "postcode", "post code", "zip code", "zipcode", "zip"]
        case .country: ["country"]
        case .currentTitle: ["current job title", "current title", "job title", "your title", "position title", "role title"]
        case .currentEmployer: ["current employer", "current company", "employer", "company name", "company", "organisation", "organization"]
        case .yearsExperience: ["years of experience", "years experience", "total experience", "experience in years"]
        case .summary: ["professional summary", "about you", "about yourself", "summary", "bio", "biography"]
        case .highestDegree: ["highest degree", "degree level", "degree type", "qualification", "degree"]
        case .fieldOfStudy: ["field of study", "major", "subject", "discipline", "course of study"]
        case .school: ["school", "university", "college", "institution", "alma mater"]
        case .graduationYear: ["graduation year", "year of graduation", "year graduated", "grad year"]
        case .linkedIn: ["linkedin profile", "linkedin url", "linkedin"]
        case .portfolio: ["portfolio", "personal website", "website", "your site", "web site", "homepage"]
        case .github: ["github profile", "github url", "github", "git hub"]
        case .noticePeriod: ["notice period", "notice", "availability to start"]
        case .salaryExpectation: [
            "salary expectation", "salary expectations", "expected salary", "desired salary",
            "compensation expectation", "expected compensation", "desired compensation",
        ]
        case .earliestStartDate: ["earliest start date", "start date", "available from", "when can you start", "availability date"]
        case .workAuthorisation: [
            "work authorisation", "work authorization", "right to work", "legally authorised",
            "legally authorized", "eligible to work", "work eligibility", "work permit",
        ]
        case .needsSponsorship: ["require sponsorship", "need sponsorship", "visa sponsorship", "sponsorship"]
        case .willingToRelocate: ["willing to relocate", "open to relocation", "relocate", "relocation"]
        case .preferredLocation: ["preferred location", "preferred work location", "location preference", "desired location"]
        case .howDidYouHear: ["how did you hear", "how did you find", "referral source", "source"]
        case .referredBy: ["referred by", "referrer", "referral name", "who referred you"]
        }
    }

    /// The plain-language name used in briefings, logs and the fill report. The
    /// agent only ever sees these names — never the values behind them.
    var briefingName: String { label.lowercased() }
}
