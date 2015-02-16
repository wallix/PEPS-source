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

type User.key = DbUtils.oid

type User.status =
   {lambda}
or {admin}
or {super_admin}

type User.fullname = {
  string fname,
  string lname
}

type User.t = {
  User.key key,
  User.status status,
  User.key creator,
  Date.date created,
  Date.date edited,
  /** Complete list of teams the user is part of. */
  list(Team.key) teams,
  int level,

  string username,
  string first_name,
  string last_name,
  Email.email email,
  option(RawFile.id) picture,
  string sgn,
  bool blocked,

  /**
   * Encryption parameters.
   *  - salt: generated at the user creation, used in PBKDF2 algorithm.
   *  - nonce: nonce used to encode the user's secret key.
   *  - publicKey, secretKey user's key pair. The secret key is encoded.
   */
  string salt,
  string nonce,
  string publicKey,
  string secretKey
}

/** User short profile, shown in the user list. */
type User.profile = {
  User.key key, string first_name, string last_name,
  User.status status, option(RawFile.id) picture, Email.email email,
  int level, list(Team.key) teams,
  // Highlightings.
  { option(string) fname,
    option(string) lname,
    option(string) sgn } highlighted
}

/** Type of the result of a page query. */
type User.page = {
  User.fullname first,
  User.fullname last,
  int size,
  bool more,
  list(User.profile) elts
}

type User.filter = {
  string name,          // Empty == unconstrained.
  list(Team.key) teams, // Empty == unconstrained.
  int level
}

type User.preferences = {
  Sidebar.view view, // FIXME: to remove
  bool notifications,
  bool search_includes_send,
  Topbar.preferences topbar,
  bool onboarding
}

/**
 * The type of passwords provided at user creation.
 * If encryption is on, the password needs to be readable in order
 * to encrypt the secret key.
 */
type User.password = string


/** Storage of user information, and association map from usernames to user keys. */
database User.t /webmail/users[{key}]
database stringmap(User.key) /webmail/userkeys  // local username -> User.key
database stringmap(User.preferences) /webmail/preferences // User display preferences.
/** Storage of user passwords (hashed). */
database stringmap(string) /webmail/passwords

/** Db defaults. */
database /webmail/users[_]/status = {lambda}
database /webmail/users[_]/blocked = {false}
database /webmail/preferences[_]/view = {icons}
database /webmail/preferences[_]/notifications = {true}
database /webmail/preferences[_]/search_includes_send = {true}
database /webmail/preferences[_]/topbar/hd/mode = {error}
database /webmail/preferences[_]/topbar/hd/mode/messages = {inbox}
database /webmail/preferences[_]/topbar/hd/display = {normal}
database /webmail/preferences[_]/onboarding = { false }

module User {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[User]", msg) }
  private function debug(msg) { Log.debug("[User]", msg) }
  private function error(msg) { Log.error("[User]", msg) }

  User.key dummy = ""
  private function keygen() { DbUtils.OID.gen() }
  function User.key idofs(string s) { s }

  both emptyFilter = {name: "", teams: [], level: 0}

  /** Convert user status to login credentials. */
  cred_of_status = function {
    case {lambda}: {user}
    case {admin}: {admin}
    case {super_admin}: {super_admin}
  }

  /** {1} User creation. */

  /** Make a new user initialized with a randomly generated key. */
  function make(User.key creator, fname, lname, username, Email.email email, level, teams) { ~{
      key: keygen(), status: {lambda},
      creator, created: Date.now(), edited: Date.now(),
      level, teams, username, first_name: fname, last_name: lname, email,
      picture: none, sgn: "",
      blocked: false, salt: "",
      secretKey: "", nonce: "", publicKey: ""
  } }

  /** Make a user profile. */
  function highlight(user, hfname, hlname, hsgn) {
    { key: user.key, first_name: user.first_name, last_name: user.last_name,
      picture: user.picture, email: user.email, status: user.status,
      teams: user.teams, level: user.level,
      // Highlightings.
      highlighted: { fname: hfname, lname: hlname, sgn: hsgn } }
  }

  /** Return the fullname of a user. */
  function fullname(user) {
    {lname: user.last_name, fname: user.first_name}
  }

  /**
   * Insert the user in the db.
   * A corresponding contact, which will act as the user profile, is constructed
   * and inserted under the user key in the contact database.
   */
  private function add(User.t user, User.password password) {
    log("add: adding user {user.username}")
    // Salt generation.
    salt = TweetNacl.randomBytes(16)
    pass = Uint8Array.decodeUTF8(password)
    // Password hashing and saving.
    hashedPass = TweetNacl.hash(Uint8Array.concat(pass, salt))
    /webmail/passwords[user.key] <- Uint8Array.encodeBase64(hashedPass)
    // Master key and key pair generation.
    masterKey = TweetNacl.pbkdf2(pass, salt, 5000, TweetNacl.SecretBox.keyLength)
    keyPair = TweetNacl.Box.keyPair()
    // Secret key encoding.
    nonce = TweetNacl.randomBytes(TweetNacl.SecretBox.nonceLength)
    secretKey = TweetNacl.SecretBox.box(keyPair.secretKey, nonce, masterKey)
    // Add all parameters to user.
    user = {user with
      publicKey: Uint8Array.encodeBase64(keyPair.publicKey),
      secretKey: Uint8Array.encodeBase64(secretKey),
      nonce: Uint8Array.encodeBase64(nonce),
      salt: Uint8Array.encodeBase64(salt)
    }
    // Register the user
    /webmail/users[key == user.key] <- user
    /webmail/userkeys[user.username] <- user.key
    get_cached_key.invalidate(user.username)
    // Build the user profile.
    Contact.profile(user) |> ignore
  }

  /**
   * Create and add a new user to the database.
   * The optional password does not have to be hashed.
   * The generated key is returned.
   */
  function new(User.key creator, fname, lname, username, Email.email email, level, teams, User.password password) {
    user = make(creator, fname, lname, username, Email.email email, level, teams) // Create user settings.
    add(user, password) // Add user.
    user // Return newly created user.
  }

  /** Insert an already constructed user in the database. */
  function insert(User.key creator, User.t user, User.password password) {
    user = { user with key:keygen(), ~creator } // Modify the key and creator.
    add(user, password)  // Add user.
  }

  /** {1} Signature settings. */

  function set_signature(key, sgn) {
    @catch(function (exn) { {failure: "{exn}"} }, {
      /webmail/users[key == key]/sgn <- sgn
      get_cached_user.invalidate(key)
      {success}
    })
  }

  /** Return the user signature, pre-formatted for message edition. */
  function get_signature(User.key key) {
    match (get(key)) {
      case { none }: ""
      case { some : user }:
        if (user.sgn == "") ""
        else "\n\n--\n{user.sgn}\n"
    }
  }

  /** {1} Password settings. */

  module Password {

    /**
     * Set the user password.
     * The secret key must be reencoded for the new password.
     */
    function set(key, oldpassword, newpassword) {
      @catch(function (exn) { {failure: "{exn}"} }, {
        data = ?/webmail/users[key == key].{salt, nonce, secretKey}
        hash = ?/webmail/passwords[key]
        match ((data, hash)) {
          case ({some: ~{salt, nonce, secretKey}}, {some: hash}):
            // String conversion.
            salt = Uint8Array.decodeBase64(salt)
            oldpass = Uint8Array.decodeUTF8(oldpassword)
            nonce = Uint8Array.decodeBase64(nonce)
            secretKey = Uint8Array.decodeBase64(secretKey)
            // Generate the master key.
            masterKey = TweetNacl.pbkdf2(oldpass, salt, 5000, TweetNacl.SecretBox.keyLength)
            // Decrypt the secret key. This act as password verification: if
            // the master key cannot open the secret key, it means the old
            // password is invalid.
            secretKey = TweetNacl.SecretBox.open(secretKey, nonce, masterKey)
            match (secretKey) {
              case {some: secretKey}:
                newpass = Uint8Array.decodeUTF8(newpassword)
                // Generate new salt and nonce.
                salt = TweetNacl.randomBytes(16)
                nonce = TweetNacl.randomBytes(TweetNacl.SecretBox.nonceLength)
                // Generate the new masterKey.
                masterKey = TweetNacl.pbkdf2(newpass, salt, 5000, TweetNacl.SecretBox.keyLength)
                // Re-encrypt the secretKey.
                secretKey = TweetNacl.SecretBox.box(secretKey, nonce, masterKey)
                // Compute the new password hash.
                hash = TweetNacl.hash(Uint8Array.concat(newpass, salt))
                // Update user and pass.
                /webmail/users[key == key] <- {
                  salt: Uint8Array.encodeBase64(salt),
                  nonce: Uint8Array.encodeBase64(nonce),
                  secretKey: Uint8Array.encodeBase64(secretKey)
                }
                /webmail/passwords[key] <- Uint8Array.encodeBase64(hash)
                {success}
              default:
                {failure: @i18n("Undefined user or invalid password")}
            }
          default: {failure: @i18n("Undefined user or invalid password")}
        }
      })
    }

    /**
     * Reset the password, and replace it by a random string.
     * As the secret key CANNOT BE RECOVERED, all access will be lost to
     * encrypted data ; a new key pair is generated.
     */
    function reset(User.key key) {
      @catch(Utils.const(none), {
        password = Random.string(10)
        keyPair = TweetNacl.Box.keyPair()
        salt = TweetNacl.randomBytes(16)
        nonce = TweetNacl.randomBytes(TweetNacl.SecretBox.nonceLength)
        pass = Uint8Array.decodeUTF8(password)
        // Generate the new masterKey.
        masterKey = TweetNacl.pbkdf2(pass, salt, 5000, TweetNacl.SecretBox.keyLength)
        // Encrypt the secretKey.
        secretKey = TweetNacl.SecretBox.box(keyPair.secretKey, nonce, masterKey)
        // Compute the new password hash.
        hash = TweetNacl.hash(Uint8Array.concat(pass, salt))
        // Update user and pass.
        /webmail/users[key == key] <- {
          salt: Uint8Array.encodeBase64(salt),
          nonce: Uint8Array.encodeBase64(nonce),
          secretKey: Uint8Array.encodeBase64(secretKey),
          publicKey: Uint8Array.encodeBase64(keyPair.publicKey)
        }
        /webmail/passwords[key] <- Uint8Array.encodeBase64(hash)
        publicKeyCache.invalidate(key)
        some(password)
      })
    }

    /** Compare the password with the one registered under the given key. */
    function verify(User.key key, string password) {
      match ((?/webmail/users[key == key]/salt, ?/webmail/passwords[key])) {
        case ({some: salt}, {some: hash}):
          pass = Uint8Array.decodeUTF8(password)
          salt = Uint8Array.decodeBase64(salt)

          TweetNacl.verify(
            Uint8Array.decodeBase64(hash),
            TweetNacl.hash(Uint8Array.concat(pass, salt))
          )
        default: false
      }
    }

  } // END PASSWORD


  /** {1} Comparators. */

  /** Return a list of the fields different between both users (all fields compared except creator, teams). */
  // function diff(User.t u1, User.t u2) {
  //   l = if (u1.first_name != u2.first_name) [{first_name}] else []
  //   l = if (u1.last_name != u2.last_name) [{last_name}|l] else l
  //   l = if (Email.to_string(u1.email) != Email.to_string(u2.email)) [{email}|l] else l
  //   l = if (u1.status != u2.status) [{status}|l] else l
  //   l = if (u1.level != u2.level) [{level}|l] else l
  //   l = if (u1.sgn != u2.sgn) [{sgn}|l] else l
  //   l = if (u1.blocked != u2.blocked) [{blocked}|l] else l
  //   if (u1.salt != u2.salt) [{salt}|l] else l
  // }

  /** Return [true] if the users are equal (all fields compared except creator, teams). */
  function equals(User.t u1, User.t u2) {
    (u1.first_name == u2.first_name) && (u1.last_name == u2.last_name) &&
    (Email.to_string(u1.email) == Email.to_string(u2.email)) &&
    (u1.status == u2.status) && (u1.level == u2.level) &&
    (u1.sgn == u2.sgn) && (u1.blocked == u2.blocked) &&
    (u1.salt == u2.salt)
  }

  /** {1} Getters (private versions). */

  private function priv_get_key(string username) {
    debug("key? {username}");
    ?/webmail/userkeys[username]
  }
  function priv_get_level(User.key key) {
    debug("level? {key}");
    ?/webmail/users[key == key]/level
  }
  private function priv_get_status(User.key key) {
    debug("status? {key}");
    ?/webmail/users[key == key]/status ? {lambda}
  }
  function priv_get_teams(User.key key) {
    ?/webmail/users[key == key]/teams ? []
  }
  /**
   * Return the minimal set of teams such that belonging to these implies
   * belonging to the complete list of teams.
   */
  function priv_get_min_teams(User.key key) {
    teams = ?/webmail/users[key == key]/teams ? []
    Team.reduce(teams)
  }
  function priv_get_user(User.key key) {
    debug("get? {key}");
    ?/webmail/users[key == key]
  }
  function priv_get_preferences(User.key key) {
    ?/webmail/preferences[key]
  }

  function get_username(User.key key) {
    Option.map(_.username, get(key))
  }
  private function priv_get_name(User.key key) {
    match (?/webmail/users[key == key].{first_name, last_name}) {
      case {some: ~{last_name, first_name}}:
        sp = if (last_name == "" || first_name == "") "" else " "
        some("{first_name}{sp}{last_name}")
      default: none
    }
  }
  function get_password(User.key key) {
    ?/webmail/passwords[key]
  }
  function get_email(User.key key) {
    Option.map(_.email, get(key))
  }
  function get_picture(User.key key) {
    Option.bind(_.picture, get(key))
  }
  /**
   * Return a profile picture associated with one the of given emails.
   * Typically used to initialize contacts with an avatar.
   */
  function get_emails_picture(list(Email.address) emails) {
    log("get_emails_picture: trying with emails {List.map(Email.address_to_string, emails) |> String.concat(",", _)}")
    DbUtils.option(/webmail/users[email.address in emails and picture.some exists]/picture) |> Option.bind(identity, _)
  }
  function get_fullname(User.key key) {
    match (get(key)) {
      case {some: user}: some({fname: user.first_name, lname: user.last_name})
      default: none
    }
  }
  function get_address(User.key key) {
    match (get_email(key)) {
      case {some: email}: {internal: ~{key, email, team: false}}
      default: {unspecified: key}
    }
  }
  function is_blocked(User.key key) { ?/webmail/users[key == key]/blocked ? false }

  /** Given a login, find which user key it corresponds to. */
  function identify(string login) {
    match (get_key(login)) {
      case {some: key}: {some: key}
      default:
        email = Email.address_of_string_opt(login)
        Option.bind(find_key_by_address, email)
    }
  }

  /** {1} Encryption. */

  /** Will cache both user and team public keys, so as to avoid continual checks. */
  private publicKeyCache =
    AppCache.sized_cache(100,
      function (User.key key) {
        if (User.key_exists(key)) ?/webmail/users[key == key]/publicKey ? ""
        else ?/webmail/teams[key == key]/publicKey ? ""
      }
    )

  /** Return the user public key (which caching). */
  exposed function publicKey(User.key key) { publicKeyCache.get(key) }
  /** Return all user encryption parameters. */
  exposed function encryption(User.key key) {
    ?/webmail/users[key == key].{nonce, salt, secretKey}
  }

  /** Function caching. */

  private get_cached_key_exists = AppCache.sized_cache(100, priv_key_exists)

  private get_cached_user = AppCache.sized_cache(100, priv_get_user)
  private get_cached_name = AppCache.sized_cache(100, priv_get_name)
  private get_cached_level = AppCache.sized_cache(100, priv_get_level)
  // These two functions are not affected by changes in the teams, as parents are immutable.
  private get_cached_min_teams = AppCache.sized_cache(100, priv_get_min_teams)
  private get_cached_teams = AppCache.sized_cache(100, priv_get_teams)
  private get_cached_key = AppCache.sized_cache(100, priv_get_key)
  private get_cached_status = AppCache.duration_cache(Duration.s(1), priv_get_status)
  private get_cached_preferences = AppCache.sized_cache(100, priv_get_preferences)

  private function invalidate_fields(User.key key) {
    get_cached_user.invalidate(key)
    get_cached_level.invalidate(key)
    get_cached_min_teams.invalidate(key)
    get_cached_teams.invalidate(key)
    get_cached_status.invalidate(key)
    get_cached_name.invalidate(key)
    // Do not forget to invalidate the label cache.
    Label.Sem.invalidate_user(key)
  }

  private function invalidate_all(User.key key) {
    invalidate_fields(key)
    get_cached_key_exists.invalidate(key)
    get_cached_preferences.invalidate(key)
  }

  /** Public, cached versions of the above. */

  @expand function key_exists(key) { get_cached_key_exists.get(key) }

  @expand function get(key) { get_cached_user.get(key) }
  @expand function get_name(key) { get_cached_name.get(key) }
  @expand function get_level(key) { get_cached_level.get(key) }
  @expand function get_key(username) { get_cached_key.get(username) }
  @expand function get_status(key) { get_cached_status.get(key) }
  @expand function get_teams(key) { get_cached_teams.get(key) }  // Note that the result is different from just user.teams
  @expand function get_min_teams(key) { get_cached_min_teams.get(key) }
  @expand function get_preferences(key) { get_cached_preferences.get(key) }

  /**
   * Return all the teams the user has admin rights over.
   * Concreately all the children of the user teams.
   */
  function get_administrated_teams(User.key key) {
    get_min_teams(key) |>
    List.map(Team.get_all_subteams, _) |>
    List.flatten
  }

  /**
   * Return the admin teams, which are at the junction between
   * user teams and administrated teams.
   */
  function get_admin_teams(User.key key) {
    get_min_teams(key) |>
    List.filter_map(Team.get, _)
  }

  /** {1} Checks and properties. */

  /** Check for pre-existant elements (private versions). */
  function username_exists(string username) {
    Option.is_some(get_key(username))
  }
  private function priv_key_exists(User.key key) {
    Db.exists(@/webmail/users[key == key])
  }

  /** Check the status. */
  function is_admin(User.key key) {
    get_status(key) == {admin}
  }
  function is_super_admin(User.key key) {
    get_status(key) == {super_admin}
  }

  /**
   * User is an administrator of a team d if either
   *   - user is super admin
   *   - user is admin and d is a sub team of one in the list of teams of user.
   */
  server function is_team_admin(User.key key, Team.key d) {
    match (get(key)) {
      case {some: user}:
        user.status == {super_admin} ||
       (user.status == {admin} &&
        List.exists(Team.is_subteam(d,_), user.teams))
      default: false
    }
  }

  /**
   * User is administrator of another user if the second is
   * is one of the teams administrated by the first.
   */
  server function is_user_admin(User.key admin, User.key user) {
    match (get(admin)) {
      case {some: admin}:
        match (get(user)) {
          case {some: user}:
            Sem.is_user_admin(admin, user)
          default: false
        }
      default: false
    }
  }

  module Sem {
    /**
     * User is an administrator of a team d if either
     *   - user is super admin
     *   - user is admin and d is a sub team of one in the list of teams of user.
     */
    server function is_team_admin(User.t user, Team.key d) {
      user.status == {super_admin} ||
     (user.status == {admin} &&
      List.exists(Team.is_subteam(d,_), user.teams))
    }

    /**
     * User is administrator of another user if the second is
     * is one of the teams administrated by the first.
     */
    server function is_user_admin(User.t admin, User.t user) {
      admin.status == {super_admin} ||
     (admin.status == {admin} && (user.teams == [] ||
      List.exists(is_team_admin(admin,_), user.teams)))
    }
  } // END SEM

  function is_in_team(User.key key, Team.key d) {
    List.mem(d, get_teams(key))
  }
  function is_in_teams(User.key key, list(Team.key) ds) {
    List.exists(is_in_team(key, _), ds)
  }

  /** {1} Modifiers. */

  function add_preferences(User.key key, User.preferences preferences) {
    /webmail/preferences[key] <- preferences;
    get_cached_user.invalidate(key)
    get_cached_preferences.invalidate(key)
  }

  /**
   * Update a user. Since all the fields are modified, it should be used
   * only on large updates. The change function musn't modify the key.
   *
   * @return [true] iff the update was successful (user present in the base).
   */
  function bool update(User.key key, (User.t -> User.t) change) {
    match (get(key)) {
      case {some:user}:
        upd = change(user)
        /webmail/users[key == user.key] <- {upd with edited: Date.now()}
        invalidate_fields(key)
        true
      default:
        false
    }
  }

  function bool update_password(User.key key, password) {
    true
    // @catch(function(exn) { false }, {
    //   /webmail/passwords[key] <- password
    //   get_cached_user.invalidate(key)
    //   true
    // })
  }

  /** {2} Field updates. */

  function bool update_level(User.key key, int level, User.status status) {
    @catch(Utils.const(false), {
      /webmail/users[key == key] <- ~{edited: Date.now(), level, status; ifexists}
      invalidate_fields(key)
      true
    })
  }

  function block(User.key key, bool block) {
    @catch(function (_) { false }, {
      /webmail/users[key == key] <- {edited: Date.now(), blocked : block; ifexists};
      get_cached_user.invalidate(key)
      true
    })
  }
  function set_email(User.key key, Email.email email) {
    @catch(function (_) { false }, {
      /webmail/users[key == key] <- {edited: Date.now(), email : email; ifexists};
      get_cached_user.invalidate(key)
      true
    })
  }
  function set_teams(User.key key, list(Team.key) teams) {
    @catch(Utils.const(false), {
      /webmail/users[key == key] <- ~{teams, edited: Date.now()}
      get_cached_user.invalidate(key)
      get_cached_teams.invalidate(key)
      get_cached_min_teams.invalidate(key)
      // Since security parameters changed, invalidate the cached security labels.
      Label.Sem.invalidate_user(key)
      true
    })
  }
  function set_level(User.key key, int level) {
    @catch(function (_) { false }, {
      /webmail/users[key == key]/level <- level
      get_cached_user.invalidate(key)
      get_cached_level.invalidate(key)
      // Since security parameters changed, invalidate the cached security labels.
      Label.Sem.invalidate_user(key)
      true
    })
  }
  function set_name(User.key key, string fname, string lname) {
    @catch(function (_) { false }, {
      /webmail/users[key == key] <- {first_name: fname, last_name: lname; ifexists}
      get_cached_user.invalidate(key)
      true
    })
  }
  function set_status(User.key key, User.status status) {
    @catch(function (_) { false }, {
      /webmail/users[key == key] <- ~{status, edited: Date.now(); ifexists}
      get_cached_user.invalidate(key)
      get_cached_status.invalidate(key)
      true
    })
  }
  function set_picture(User.key key, option(RawFile.id) picture) {
    @catch(function (_) { false }, {
      /webmail/users[key == key] <- ~{picture, edited: Date.now(); ifexists}
      get_cached_user.invalidate(key)
      true
    })
  }

  function remove(User.key key, string pass) {
    if (Password.verify(key, pass)) unsafe_remove(key)
    else error(@i18n("Delete: invalid password provided for user [{key}]"))
  }

  function unsafe_remove_password(User.key key) {
    Db.remove(@/webmail/passwords[key]);
  }

  function unsafe_remove(User.key key) {
    match (get(key)) {
      case {some: user}:
        Db.remove(@/webmail/users[key == key])
        Db.remove(@/webmail/userkeys[user.username])
        Db.remove(@/webmail/passwords[key])
        Db.remove(@/webmail/preferences[key])
        invalidate_all(key)
        get_cached_key.invalidate(user.username)
        ignore(Search.User.delete(user.key))
      default: void
    }
  }

  /** {1} Querying. */

  // FIXME: COMPLEXITY is not acceptable
  function count(list(Team.key) teams) {
    if (teams == []) DbSet.iterator(/webmail/users.{}) |> Iter.count(_)
    else DbSet.iterator(/webmail/users[teams[_] in teams].{}) |> Iter.count(_)
  }
  function iterator() {
    DbSet.iterator(/webmail/users[order -last_name,-first_name])
  }
  function list() {
    Iter.to_list(iterator())
  }
  function iterator_in(list(User.key) keys) {
    DbSet.iterator(/webmail/users[key in keys])
  }
  function list_in(list(User.key) keys) {
    Iter.to_list(iterator_in(keys))
  }
  function iterator_key() {
    DbSet.iterator(/webmail/users[]/key)
  }
  function list_key() {
    iterator_key() |> Iter.to_list
  }

  /** List all users with all least one department in the given list. */
  function list_emails_in_teams(list(Team.key) teams, list(Email.email) exclusions) {
    DbSet.iterator(/webmail/users[not(email in exclusions) and teams[_] in teams].{key, email}) |>
    Iter.to_list
  }

  function option(User.t) find_by_email(Email.email email) {
    DbUtils.uniq(/webmail/users[email == email])
  }

  function option(User.key) find_key_by_address(Email.address addr) {
    DbUtils.uniq(/webmail/users[email.address == addr]/key)
  }

  /**
   * List all the users in a list of teams.
   */
  function iter(User.t) find_by_team(int level, list(Team.key) teams) {
    match (teams) {
      case []: DbSet.iterator(/webmail/users[level >= level])
      default: DbSet.iterator(/webmail/users[level >= level and teams[_] in teams])
    }
  }
  /**
   * List all the users matching a classified label restriction.
   */
  function find_matching_restriction(restriction) {
    Iter.filter(
      function (user) { Label.check_teams(get_teams(user.key), restriction.teams) },
      DbSet.iterator(/webmail/users[level >= restriction.level]))
  }

  /**
   * Team filter: Return ALL users in team.
   * Use with caution.
   * @return a list of users with fields: key, email.
   */
  function get_team_users(list(Team.key) teams) {
    match (teams) {
      case []:     Iter.empty
      case [team]: DbSet.iterator(/webmail/users[teams[_] == team].{key, email})
      default:     DbSet.iterator(/webmail/users[teams[_] in teams].{key, email})
    }
  }

  /**
   * Fetch a total of {chunk} users from the database.
   * Only users matching the following condition are returned:
   *  - ability to read the given class.
   *  - not in excluded users.
   *  - matching the filter.
   */
  protected function fetch(User.fullname last, int chunk, Label.id class, User.filter filter, list(User.key) excluded) {
    classFilter = Label.userFilter(class) // Fetch the class definition in order to adapt the filter.
    teams = List.rev_append(classFilter.teams, filter.teams) |> List.unique_list_of // Join filters.
    name = filter.name
    level = classFilter.level-1
    if (teams == [] && name == "")
      DbSet.iterator(/webmail/users[
        (last_name > last.lname or (last_name == last.lname and first_name > last.fname)) and
        level > level and not(key in excluded); limit chunk; order +last_name, +first_name
      ])
    else if (name == "")
      DbSet.iterator(/webmail/users[
        (last_name > last.lname or (last_name == last.lname and first_name > last.fname)) and
        level > level and teams[_] in teams and not(key in excluded);
        limit chunk; order +last_name, +first_name
      ])
    else if (teams == [])
      DbSet.iterator(/webmail/users[
        (last_name > last.lname or (last_name == last.lname and first_name > last.fname)) and
        (first_name =~ name or last_name =~ name) and level > level and not(key in excluded);
        limit chunk; order +last_name, +first_name
      ])
    else
      DbSet.iterator(/webmail/users[
        (last_name > last.lname or (last_name == last.lname and first_name > last.fname)) and
        (first_name =~ name or last_name =~ name) and level > level and teams[_] in teams and
        not(key in excluded); limit chunk; order +last_name, +first_name
      ])
  }

  /**
   * Specific function which filters only teams.
   * @param optteams the user must be in at least one of those teams.
   */
  protected function fetch_teams(User.fullname last, int chunk, optteams) {
    DbSet.iterator(/webmail/users[
      last_name > last.lname or (last_name == last.lname and first_name > last.fname) and
      (teams[_] in optteams); limit chunk; order +last_name, +first_name
    ])
  }

  /**
   * Create a filter that accepts only the labels that can be used by the given user.
   * @param cat the kind of filtered labels.
   */
  exposed function make_label_filter(User.key key, what) {
    match (what) {
      case {class}
      case {all}:
        match (get(key)) {
          case {some: user}:
            level = {level: user.level+1, cmp: {lt}}
            teams =
              if (user.teams == []) [{noteam}]
              else [{disj: List.map(function (t) {{team: t}}, user.teams)}]
            [level|teams]
          default: []
        }
      default: []
    }
  }

  /**
   * Email address autocompletion.
   * Return the list of users membersof the given teams and matching the
   * provded term.
   */
  function autocomplete(list(Team.key) teams, string term) {
    DbSet.iterator(/webmail/users[teams[_] in teams and (first_name =~ term or last_name =~term)].{first_name, last_name, email}) |>
    Iter.fold(function (user, acc) {
      name = some("{user.first_name} {user.last_name}")
      elt =
        { label: Email.to_string({user.email with ~name}),
          value: Email.to_string(user.email) }
      [elt|acc]
    }, _, [])
  }

  /** {1} Conversions. */

  /** Parsing. */
  function option(User.status) status_of_string(string status) {
    match (status) {
      case "super_admin": {some: {super_admin}}
      case "admin": {some: {admin}}
      case "lambda": {some: {lambda}}
      default: {none}
    }
  }

  function status_to_string(User.status status) {
    match (status) {
      case {lambda}: "lambda"
      case {admin}: "admin"
      case {super_admin}: "super_admin"
    }
  }


  function to_full_name(User.t user) {
    sp = if (user.first_name == "" || user.last_name == "") "" else " "
    "{user.first_name}{sp}{user.last_name}"
  }

}
