/*
 * PEPS is a modern collaboration server
 * Copyright (C) 2015 MLstate
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */


package com.mlstate.webmail.model

type Contact.id = DbUtils.oid

type Contact.visibility =
  {hidden} or // i don't want to see this contact in my contacts list
  {secret} or // only me can see my contacts
  {friendly} or // me and my contacts can see my contacts
  {world} // everybody can see my contacts

type Contact.status =
  {blocked} or // I don't want to see messages from this contact.
  {vip} or // Show me his messages in priority.
  {normal} // YAC.

type Contact.phoneNumber = string
type Contact.email = Email.address
type Contact.im = string
type Contact.photo = RawFile.id // RawFile with image type, and hopefully a thumbnail.
type Contact.category = string
type Contact.url = string

type Contact.name = {
  string formatted, // The complete name of the contact
  string familyName, // The contacts family name
  string givenName, // The contacts given name
  string middleName, // The contacts middle name
  string honorificPrefix, // The contacts prefix (example Mr. or Dr.)
  string honorificSuffix, // The contacts suffix (example Esq.)
}

type Contact.address = {
  bool pref, // Set to true if this ContactAddress contains the user's preferred value
  string atype, // A string that tells you what type of field this is (example: 'home')
  string formatted, // The full address formatted for display
  string streetAddress, // The full street address
  string locality, // The city or locality
  string region, // The state or region
  string postalCode, // The zip code or postal code
  string country, // The country name
}

type Contact.organization = {
  bool pref, // Set to true if this ContactOrganization contains the user's preferred value
  string otype, // A string that tells you what type of field this is (example: 'home')
  string name, // The name of the organization
  string team, // The team the contract works for
  string title // The contacts title at the organization
}

/** Adding information and weight to pieces of contact information. */
type Contact.item('a) = {string kind, 'a elt}
type Contact.items('a) = list(Contact.item('a))

// based on Apache Cordova implementation
type Contact.info = {
  string displayName,          // The name of this Contact, suitable for display to end-users
  string nickname,             // A casual name to address the contact by
  Contact.name name,           // An object containing all components of a persons name
  option(Date.date) birthday,  // The birthday of the contact
  string note,                 // A note about the contact. (DOMString)
  Contact.items(Contact.phoneNumber)  phoneNumbers,  // An array of all the contact's phone numbers
  Contact.items(Contact.email)        emails,        // An array of all the contact's email addresses
  Contact.items(Contact.address)      addresses,     // An array of all the contact's addresses
  Contact.items(Contact.im)           ims,           // An array of all the contact's IM addresses
  Contact.items(Contact.organization) organizations, // An array of all the contact's organizations
  Contact.items(Contact.photo)        photos,        // An array of the contact's photos
  Contact.items(Contact.category)     categories,    // An array of all the contacts user defined categories
  Contact.items(Contact.url)          urls           // An array of web pages associated to the contact
}

type Contact.t = {
  Contact.id id,                 // Unique contact id; immutable.
  User.key owner,                // Contact owner; immutable.
  Contact.visibility visibility,
  Contact.status status,
  Contact.info info
}

/** Client contact, decorated with highlights. */
type Contact.client_contact = {
  Contact.t contact,
  option(string) highlighted_emails,
  option(string) highlighted_name,
  option(string) highlighted_displayName
}

database Contact.t /webmail/addrbook/contacts[{id}]
database /webmail/addrbook/contacts[_] full

/**
 * Reversed indexing: associating an email address to a contact.
 * Also contains the weight of the address, for fast updates.
 */
type Contact.Email.info = {
  User.key owner,
  Email.address email, // Key. Email is specific to a registered user.
  string name,         // Contact's displayName.
  Contact.id contact,
  int weight
}

database Contact.Email.info /webmail/addrbook/index[{email, owner}]
database /webmail/addrbook/index[_] full

module Contact {

  /** {1} Utils. */

  private function log(msg) { Log.notice("Contact: ", msg) }

  function genid() { DbUtils.OID.gen() }
  dummy = ""

  /** {1} Construction. */

  empty_contact_name = {
    formatted: "",
    familyName: "",
    givenName: "",
    middleName: "",
    honorificPrefix: "",
    honorificSuffix: ""
  }

  empty_contact_address = {
    pref: false,
    atype: "empty",
    formatted: "",
    streetAddress: "",
    locality: "",
    region: "",
    postalCode: "",
    country: ""
  }

  empty_contact_organization = {
    pref: false,
    otype: "empty",
    name: "",
    team: "",
    title: ""
  }

  empty_info = {
    displayName: "",
    name: empty_contact_name,
    nickname: "",
    phoneNumbers: [],
    emails: [],
    addresses: [],
    ims: [],
    organizations: [],
    birthday: none,
    note: "",
    photos: [],
    categories: [],
    urls: []
  }

  empty_contact = {
    id: "",
    owner: "",
    visibility: {friendly},
    status: {normal},
    info: empty_info
  }

  /**
   * Create a new contact.
   * @param email the default contact email (needed for minimal configuration), of category 'home'.
   */
  function make(User.key owner, string name, email, visibility) {
    info = {
      empty_info with
      displayName: name,
      emails: [{kind: "home", elt: email}]
    }
   ~{ id: genid(), owner, visibility, status: {normal}, info }
  }

  /**
   * Lookup contact emails matching the queried term.
   * Returned emails are sorted by associated weight.
   */
  function autocomplete(User.key owner, string term) {
    contacts =
      DbSet.iterator(/webmail/addrbook/contacts[
        owner == owner and (
          info.displayName =~ term or
          info.emails[_].elt.local =~ term
        )
      ].{info}) |> Iter.to_list

    emails = List.fold(function (contact, acc) {
      List.rev_map(_.elt, contact.info.emails) |>
      List.rev_append(_, acc) }, contacts, [])
    sorted =
      DbSet.iterator(/webmail/addrbook/index[
        owner == owner and email in emails and
        (name =~ term or email.local =~ term); order +weight].{name, email}) |>
      Iter.to_list |>
      List.map(function (item) {
        name = if (item.name == "") none else some(item.name)
        email = Email.to_string({name: name, address: item.email})
        { id: Email.address_to_string(item.email),
          text: email }
      }, _)
    sorted
  }

  /** {1} Modifications of the database. */

  /** {2} Indexing. */

  /**
   * Index a contact by its email address.
   * All formerly registered emails are overridden.
   */
  function index(Contact.t contact) {
    List.iter(function (item) {
      /webmail/addrbook/index[{email: item.elt, owner: contact.owner}] <- {
        contact: contact.id, name: contact.info.displayName,
        email: item.elt, owner: contact.owner, weight: 1
      }
    }, contact.info.emails)
  }

  /**
   * Reverse operation. The function tries reindexing the emails to new contacts
   * before removing the index in memory.
   * CAUTION: to avoid reindexing to the same contact, delete the original contact first.
   */
  function unindex(Contact.t contact) {
    List.iter(function (item) { unregister(contact.id, contact.owner, item.elt) }, contact.info.emails)
  }

  /**
   * Looks up a contact using the given address, and add it to the index.
   * Call after unindexing contact emails.
   * @return [true] if the address was successfullt reindexed.
   */
  function reindex(User.key owner, Email.address email) {
    contact = DbUtils.option(/webmail/addrbook/contacts[owner == owner and info.emails[_].elt == email].{id, info})
    match (contact) {
      case {some: contact}:
        /webmail/addrbook/index[~{email, owner}] <- {contact: contact.id, name: contact.info.displayName}
        true
      default: false
    }
  }

  /** Register a new email address for the given contact. */
  function register(Contact.id contact, string name, User.key owner, Email.address email) {
    /webmail/addrbook/index[~{email, owner}] <- ~{contact, name, email, owner, weight: 1}
  }

  /** Idem. */
  function unregister(Contact.id contact, User.key owner, Email.address email) {
    // Check that the email is indeed connected with the given contact.
    // Necessary ?
    match (find(owner, email)) {
      case {some: info}:
        // Try reindexing the email before removing the index.
        if (info.contact == contact && not(reindex(owner, email)))
          Db.remove(@/webmail/addrbook/index[~{email, owner}])
      default: void
    }
  }

  /**
   * Increment the use count of the given email address.
   * @return [true] iff the count was successfully incremented. In particular, return false if the address does not exist.
   */
  function mark(User.key owner, Email.address email, int increment) {
    if (indexed(owner, email)) {
      /webmail/addrbook/index[~{email, owner}] <- {weight+=increment}
      true
    } else false
  }

  /** {2} Adding contacts. */

  /** Add a contact to the database, and index the email addresses used. */
  function insert(Contact.t contact) {
    /webmail/addrbook/contacts[id == contact.id] <- contact
    index(contact)
    get_cached.invalidate(contact.id)
  }

  /** Create a new contact, no checks. */
  function new(User.key owner, option(string) name, Email.address email, visibility) {
    make(owner, name ? "", email, visibility) |> with_picture |> insert
  }

  /** If available, import a profile picture attached to one of the addresses to fill in the contact. */
  function with_picture(contact) {
    if (contact.info.photos == []) {
      emails = List.map(_.elt, contact.info.emails)
      picture = User.get_emails_picture(emails)
      photos = match (picture) {
        case {some: rawid}: [{kind: "work", elt: rawid}]
        default: []
      }
      {contact with info.photos: photos}
    } else contact
  }

  /**
   * Assign an avatar to all contacts with one of the given mail addresses and which do not
   * have a picture yet. This funciton should be called after setting the user picture in the
   * profile settings.
   */
  function addPicture(list(Email.address) emails, RawFile.id photo) {
    /webmail/addrbook/contacts[
      info.emails[_].elt in emails and   // Correct email.
      info.photos == []                 // No set user picture.
    ] <- {info.photos: [{kind: "work", elt: photo}]}
  }

  /** Create the contact associated with the provided user. */
  protected function profile(User.t user) {
    // Build the user profile. The contact's owner key is the new user.
    // The new contact is hidden, so as to not appear in the contact list.
    fullname =
      sp = if (user.first_name == "" || user.last_name == "") "" else " "
      "{user.first_name}{sp}{user.last_name}"
    contact = {Contact.make(user.key, fullname, user.email.address, {hidden}) with id: user.key}
    Contact.insert(contact)
    contact
  }

  /**
   * Initialize the contact list of the given user.
   * All users from the given teams are imported.
   */
  protected function init(User.key key, list(Team.key) teams) {
    User.list_emails_in_teams(teams, []) |>
    List.iter(function (user) {
      make(key, Email.to_name(user.email), user.email.address, {secret}) |> insert
    }, _)
  }

  /**
   * Same behaviour as Contact.init, except the function checks for duplicates in
   * the previous contact list (Contact.init assumes the list is initially empty).
   */
  function import(User.key key, list(Team.key) teams) {
    User.list_emails_in_teams(teams, []) |>
    List.iter(function (user) {
      match (find(key, user.email.address)) {
        case {some: _}: void
        default:
          // Create new contact.
          new(key, user.email.name, user.email.address, {secret})
      }
    }, _)
  }

  /** Delete and unindex the given contact. */
  function remove(Contact.id id) {
    match (get(id)) {
      case {some: contact}:
        Db.remove(@/webmail/addrbook/contacts[id == id])
        unindex(contact) // Keep after the modification of the db.
        get_cached.invalidate(id)
      default: void
    }
  }

  /**
   * Apply an update function to a contact in the list.
   * The change function can modify the list of emails of the contact,
   * in which case the index is updated.
   * What cannot be modified: owner, id.
   */
  function update(Contact.id id, (Contact.t -> Contact.t) update) {
    match (get(id)) {
      case {some: contact}:
        newcontact = update(contact)
        // Updating the contacts.
        /webmail/addrbook/contacts[id == id] <- {newcontact with ~id, owner: contact.owner} // Ensuring immutability of owner, id.
        get_cached.invalidate(id)
        // Updating the index.
        List.iter(function (newitem) {
          added = List.for_all(function (item) { item.elt != newitem.elt }, contact.info.emails)
          if (added) register(id, contact.info.displayName, contact.owner, newitem.elt)
          else if (newcontact.info.displayName != contact.info.displayName)
            /webmail/addrbook/index[{owner:contact.owner, email:newitem.elt}] <- {name: newcontact.info.displayName}
        }, newcontact.info.emails)
        List.iter(function (item) {
          removed = List.for_all(function (newitem) { newitem.elt != item.elt }, newcontact.info.emails)
          if (removed) unregister(id, contact.owner, item.elt)
        }, contact.info.emails)
        // Updating solr search index.
        // Search.unbook(key, email) |> ignore
      default: void
    }
  }

  /** Update the visibility of a contact in the list. */
  function set_visibility(Contact.id id, Contact.visibility visibility) {
    /webmail/addrbook/contacts[id == id] <- ~{visibility; ifexists}
    get_cached.invalidate(id)
  }

  /** Block or unblock a contact in the list. */
  function set_status(Contact.id id, Contact.status status) {
    /webmail/addrbook/contacts[id == id] <- ~{status; ifexists}
    get_cached.invalidate(id)
  }

  /** Block or unblock a contact in the list. */
  function set_picture(Contact.id id, RawFile.id picture) {
    /webmail/addrbook/contacts[id == id] <- ~{info.photos: [{kind: "photo", elt: picture}]; ifexists}
    get_cached.invalidate(id)
  }

  /**
   * Replace the contact in memory. Useful to set an undeterminate number of
   * fields. To avoid changes to the id or owner that would corrupt the db,
   * these fields are reset using the previous values.
   */
  @expand function set(Contact.id id, Contact.t contact) {
    update(id, Utils.const(contact))
  }

  /** Modify the display name. */
  function rename(Contact.id id, string name) {
    /webmail/addrbook/contacts[id == id] <- {info.displayName: name; ifexists}
    get_cached.invalidate(id)
  }

  /** {1} Getters. */

  private function priv_get(Contact.id id) {
    ?/webmail/addrbook/contacts[id == id]
  }
  function get_all(User.key key) {
    DbSet.iterator(/webmail/addrbook/contacts[owner == key]) |> Iter.to_list
  }

  private get_cached = AppCache.sized_cache(100, priv_get)

  @expand function get(User.key key) { get_cached.get(key) }

  /** {1} Queries. */

  /** {2} Indexing. */

  /** Check whether an email address is already registered. */
  function indexed(User.key owner, Email.address email) {
    ?/webmail/addrbook/index[~{email, owner}].{} |> Option.is_some
  }

  /** Check whether the contact the email is associated with is blocked. */
  function blocked(User.key owner, Email.address email) {
    match (find(owner, email)) {
      case {some: info}:
        Option.map(
          function (contact) { contact.status=={blocked} },
          get(info.contact)
        ) ? false
      default: false
    }
  }

  function find(User.key owner, Email.address email) {
    ?/webmail/addrbook/index[~{email, owner}]
  }

  function find_all(User.key owner, list(Email.address) emails) {
    DbSet.iterator(/webmail/addrbook/index[owner == owner and email in emails]) |> Iter.to_list
  }

  /**
   * Return the weight of an indexed email.
   * Defaults to 0 if the email is not indexed.
   */
  function weight(User.key owner, Email.address email) {
    weight = ?/webmail/addrbook/index[~{email, owner}].{weight} |> Option.map(_.weight, _)
    weight ? 0
  }

  /** Sort a list of emails by decreasing weight. */
  function sort(User.key owner, list(Email.address) emails) {
    DbSet.iterator(/webmail/addrbook/index[owner == owner and email in emails; order +weight].{name, email}) |>
    Iter.to_list
  }

  /** {2} Contacts. */

  /**
   * Return the total number of contacts stored in the database.
   * Expensive with large dbs ; use with caution.
   */
  function count() {
    DbSet.iterator(/webmail/addrbook/contacts.{}) |> Iter.count
  }

  /** Return the list of contacts with id in the given list. */
  function iterator(list(Contact.id) ids) {
    DbSet.iterator(/webmail/addrbook/contacts[id in ids])
  }
  function list(list(Contact.id) ids) {
    iterator(ids) |> Iter.to_list
  }

  /** Return the contact picture. */
  function get_picture(Contact.id id) {
    match (?/webmail/addrbook/contacts[id == id].{info}) {
      case {some: {info: {photos: [~{kind, elt} | _] ...}}}: some(elt)
      default: none
    }
  }

  /** {1} Conversions. */

  /** Return the most indicative piece of contact information to use
   * as name. Successive tries:
   *   - displayName
   *   - emails
   *    ?
   */
  function name(Contact.t contact) {
    if (contact.info.displayName != "") contact.info.displayName
    else
      match (contact.info.emails) {
        case [item|_]: Email.address_to_string(item.elt)
        default: ""
      }
  }

  string_of_visibility = function {
    case {hidden}: "hidden"
    case {secret}: "secret"
    case {friendly}: "friendly"
    case {world}: "world"
  }

  visibility_of_string = function {
    case "hidden": {hidden}
    case "secret": {secret}
    case "friendly": {friendly}
    case "world": {world}
    default: {hidden}
  }

  function to_client_contact(Contact.t contact) {
   ~{ contact,
      highlighted_emails: none,
      highlighted_name: none,
      highlighted_displayName: none }
  }

  /** Import a contact from a ldap source. */
  function outcome(Contact.t, string) of_json(RPC.Json.json json) {
    // Add a kind to a list of elements.
    function kinded(string kind, elts) {
      List.rev_map(function (elt) { ~{kind, elt} }, elts)
    }
    // Parse the contact.
    match (WebmailContact.parseJson(json)) {
      case {success: Ldap.webmailContact wc}:
        workAddress = {
          pref:false, atype:"work", formatted:"",
          streetAddress:Utils.sofl(wc.street), locality:Utils.sofl(wc.l),
          region:Utils.sofl(wc.st), postalCode:Utils.sofl(wc.postalCode), country:""
        }
        Contact.name name = {
          formatted:Utils.sofo(wc.displayName),
          familyName:Utils.sofl(wc.sn),
          givenName:Utils.sofl(wc.givenName),
          middleName:"",
          honorificPrefix:"",
          honorificSuffix:""
        }
        Contact.organization workOrganization = {
          pref: false, otype: "work",
          name: Utils.sofl(wc.o), title: "",
          team: ""
        }
        Contact.info info = {
          displayName: Utils.sofo(wc.displayName), ~name,
          nickname: Utils.sofl(wc.uid), // Need to ensure uniqueness
          phoneNumbers:
            kinded("work", wc.telephoneNumber) |> List.rev_append(
            kinded("home", wc.homePhone) |> List.rev_append(
            kinded("mobile", wc.mobile) |> List.rev_append(
            kinded("fax", wc.facsimileTelephoneNumber), _), _), _),
          addresses: [{kind: "work", elt: workAddress}],
          organizations: [{kind: "work", elt: workOrganization}],
          photos: List.map(RawFile.idofs, wc.photo) |> kinded("photo", _),
          emails: List.map(Email.address_of_string, wc.mail) |> kinded("home", _),
          urls: kinded("url", wc.labeledURI),

          ims: [], categories: [],
          birthday: none, note: Utils.sofo(wc.description)
        }

        if (wc.webmailContactId == none || wc.webmailContactId == {some: ""})
          {failure: @intl("No contact id")}
        else
          { success: {
              owner: "", id: wc.webmailContactId ? genid(),
              visibility: Contact.visibility_of_string(wc.webmailContactVisibility ? ""),
              status:
                if (wc.webmailContactBlocked ? false) { {blocked} }
                else { {normal} },
              ~info
            } }
      case ~{failure}:
        error("Contact.of_json: failed to parse the contact: {failure}") |> ignore
        ~{failure}
    }
  }

  /** Export a contact as a webmail contact. */
  function format_contact_name(Contact.name name) {
    function mrg(f,s) {
      sp = if (f == "" || s == "") "" else " "
      "{f}{sp}{s}"
    }
    mrg(mrg(name.honorificPrefix,mrg(mrg(name.givenName,name.middleName),name.familyName)),name.honorificSuffix)
  }
  function format_contact_address(Contact.address address) {
    [ address.streetAddress,
      address.locality,
      address.region,
      address.postalCode,
      address.country ]
  }
  /** Retrieve elements of a list with a pareticular kind. */
  private function with_kind(string kind, items) {
    List.fold(function (item, acc) {
      if (item.kind == kind) [item.elt|acc]
      else acc
    }, items, [])
  }
  /** Same as with_kind, but returns only the first element with the given kind. */
  private function with_kind_uniq(string kind, items) {
    match (items) {
      case []: none
      case [item|rem]:
        if (item.kind == kind) {some: item.elt}
        else with_kind_uniq(kind, rem)
    }
  }
  function outcome(Ldap.webmailContact, string) to_wcontact(Contact.t contact) {
    if (contact.info.name.familyName == "")
      {failure:"Ldap.add: {@intl("Bad contact, no last name")}"}
    else if (contact.info.nickname == "")
      {failure:"Ldap.add: {@intl("Bad contact, no nickname")}"}
    else {
      workAddress = with_kind_uniq("work", contact.info.addresses) ? Contact.empty_contact_address
      homeAddress = with_kind_uniq("home", contact.info.addresses) ? Contact.empty_contact_address
      workOrganization = with_kind_uniq("work", contact.info.organizations) ? Contact.empty_contact_organization
      { success: {
        dn: none,
        // person
        sn: [contact.info.name.familyName], // can't be empty
        cn: [format_contact_name(contact.info.name)], // can't be empty
        userPassword: none, // Not used for contacts
        seeAlso: none, // It's actually an LDAP DN, not useful here
        description: Utils.oofs(contact.info.note), // probably not (note is Dom)

        //organizationalPerson
        title: with_kind("", contact.info.organizations) |> List.rev_map(_.title, _),
        x121Address:[], // not used
        registeredAddress:[], // not used
        destinationIndicator:[], // not used
        preferredDeliveryMethod:{none}, // not used
        telexNumber:[], // not used
        teletexTerminalIdentifier:[], // not used
        telephoneNumber: with_kind("work", contact.info.phoneNumbers),
        internationalISDNNumber:[], // not used
        facsimileTelephoneNumber: with_kind("fax", contact.info.phoneNumbers),
        street:Utils.lofs(workAddress.streetAddress),
        postOfficeBox:[], // not used
        postalCode:Utils.lofs(workAddress.postalCode),
        postalAddress:[], // Utils.lofs(workAddress.formatted)???
        physicalDeliveryOfficeName:[], // not used
        ou:["People"], // organizationalUnitName
        st:Utils.lofs(workAddress.region), // state or province
        l:Utils.lofs(workAddress.locality), // localityName
        // c:Utils.lofs(workAddress.country), // countryName is missing from inetOrgPerson !!!

        // inetOrgPerson
        audio:[], // not used
        businessCategory:[], // not used
        carLicense:[], // not used
        teamNumber:[], // not used
        displayName:Utils.oofs(contact.info.displayName),
        employeeNumber:{none}, // not used
        employeeType:[], // not used
        givenName:Utils.lofs(contact.info.name.givenName),
        homePhone:with_kind("home",contact.info.phoneNumbers),
        homePostalAddress:format_contact_address(homeAddress),
        initials:[], // not used
        jpegPhoto:[], // not used
        labeledURI:with_kind("",contact.info.urls),
        mail: List.map(function (item) { Email.address_to_string(item.elt) }, contact.info.emails),
        manager:[], // not used
        mobile:with_kind("mobile",contact.info.phoneNumbers),
        o:Utils.lofs(workOrganization.name),
        pager:[], // not used
        photo: with_kind("",contact.info.photos) |> List.map(RawFile.sofid, _),
        roomNumber:[], // not used
        secretary:[], // not used
        uid:Utils.lofs(contact.info.nickname), // ??? check this
        userCertificate:[], // not used
        x500uniqueIdentifier:[], // not used
        preferredLanguage:{none}, // not used
        userSMIMECertificate:[], // not used
        userPKCS12:[], // not used

        // webmailContact
        webmailContactId: {some: contact.id},
        webmailContactVisibility: {some: Contact.string_of_visibility(contact.visibility)},
        webmailContactBlocked: {some: contact.status=={blocked} },
      } }
    }
  }

}
