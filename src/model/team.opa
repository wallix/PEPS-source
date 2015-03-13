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


type Team.key = DbUtils.oid

/**
 * Type of teams.
 * All fields immutable but: name, color, description
 */
type Team.t = {
  Team.key key,
  string name,
  option(Team.key) parent,
  User.key creator,
  Date.date created,
  Date.date edited,
  string description,
  string color,
  int count, // User count.
  // Shared objects.
  Directory.id directory,
  Label.id security,
  Email.email email,
  /**
   * Same as users, teams have a public key used to
   * encrypt / decrypt PEPS messages. The secret key is
   * stored at the same path as users' (/webmail/secretKeys).
   */
  string publicKey
}

database Team.t /webmail/teams[{key}]

database /webmail/teams[_]/color = "aquamarine"
database stringmap(Team.key) /webmail/teamkeys  // name -> key

/*
 * Storage of team secret keys. User secret keys are encrypted using PBKDF2,
 * and don't need to be stored in a particular collection.
 * TODO find a way to protect team secret keys.
 */
database stringmap(string) /webmail/secretKeys

module Team {

  /** {1} Utils. */

  private function log(msg) { Log.notice("Team:", msg) }
  private function keygen() { DbUtils.OID.gen() }

  @expand function Team.key idofs(string s) { s }

  /**
   * Create the email address of a team, based upon its path.
   * If the team is unattributed, then the address can be {team}@{domain}, else the address will be
   * {parent}.{team}@{domain}.
   */
  function email(string name, option(Team.key) parent, string domain) {
    local =
      match (Message.Address.identify(name)) {
        case {some: _}:
          match (Option.bind(get_email, parent)) {
            case {some: email}: "{email.address.local}.{name}"
            default: "teams.{name}"
          }
        default: name
      }

    { name: some(name),
      address: ~{local, domain } }
  }

  /** {1} Team creation. */

  function Team.t make(User.key creator, string name, Email.email email, option(Team.key) parent, string description) {
    key = keygen()
    directory =
      parent = Option.bind(get_directory, parent)
      Directory.create(key, name, parent)
    security =
      descr = @i18n("Automatically generated, for use by users of team {name}")
      cat = {classified: {
        level: 1,
        teams: [[key]],
        encrypt: false
      }}
      Label.new(key, name, descr, cat)

   ~{ key, name, parent, creator, description, color:"aquamarine",
      created: Date.now(), edited: Date.now(), count: 0,
      directory: directory.id, security: security.id, email,
      publicKey: "" }
  }

  /** Add a new team to the database. */
  function Team.t new(User.key creator, string name, Email.email email, option(Team.key) parent, string description) {
    team = make(creator, name, email, parent, description)
    // Generation of a box keyPair.
    keyPair = TweetNacl.Box.keyPair()
    team = {team with publicKey: Uint8Array.encodeBase64(keyPair.publicKey)}
    /webmail/secretKeys[team.key] <- Uint8Array.encodeBase64(keyPair.secretKey)
    // Insertion of the team.
    /webmail/teams[key == team.key] <- team
    /webmail/teamkeys[name] <- team.key
    get_cached_key.invalidate(name)
    Option.iter(get_cached_children.invalidate, parent)
    team
  }

  /**
   * Either return the team identified by the path, if it exists, or creates it.
   * @param domain needed to generate the team mail address.
   * @return {none} if the path is empty, else the matching team.
   */
  function new_from_path(User.key creator, string domain, list(string) path) {
    List.fold(function (name, parent) {
      maybe = DbSet.iterator(/webmail/teams[parent == parent and name == name]/key)
      match (maybe.next()) {
        case {some: (d,_)}: {some: d}
        default:
          email = Team.email(name, parent, domain)
          team = new(creator, name, email, parent, @i18n("Automatically generated during Bulk import"))
          {some: team.key}
      }
    }, path, {none})
  }

  /**
   * Check for pre-existant elements (private versions).
   * The scope of a team name is limited to the path.
   */
  function team_exists(string name, option(Team.key) parent) {
    DbUtils.option(/webmail/teams[name == name and parent == parent]/key) |>
    Option.is_some
  }
  private function priv_key_exists(Team.key key) {
    Db.exists(@/webmail/teams[key == key])
  }

  /** Return the set of greatest lower bounds of the the given list of teams. */
  function reduce(list(Team.key) teams) {
    List.filter(function (team) {
      children = get_children_key(team)
      List.for_all(function (c) { not(List.mem(c, teams)) }, children)
    }, teams)
  }

  /** {1} Getters. */

  private function priv_get_team(Team.key key) { ?/webmail/teams[key == key] }
  private function priv_get_key(string name) { ?/webmail/teamkeys[name] }
  private function priv_get_name(Team.key key) { ?/webmail/teams[key == key]/name }
  private function priv_get_path(Team.key key) {
    recursive function list(Team.key) aux(key, acc) {
      match (/webmail/teams[key == key]/parent) {
        case {some: d}: aux(d, [key|acc])
        case {none}: [key|acc]
      }
    }
    aux(key, [])
  }
  private function list(Team.t) priv_get_children(Team.key key) {
    DbSet.iterator(/webmail/teams[parent == {some: key}; order +name]) |>
    Iter.to_list
  }
  private function list(Team.key) priv_get_children_key(Team.key key) {
    DbSet.iterator(/webmail/teams[parent == {some: key}; order +name]/key) |>
    Iter.to_list
  }

  private function priv_get_all_subteams(Team.key team) {
    all =
      DbSet.iterator(/webmail/teams[parent == {some: team}]/key) |>
      Iter.to_list |>
      List.map(priv_get_all_subteams, _) |>
      List.flatten
    [team|all]
    // Note:
    // Using get_cached_subteams for the recursive call would be better,
    // but Opa can't do that (risk of cache referencing itself).
  }

  /** Function caching. */

  private get_cached_key_exists = AppCache.sized_cache(100, priv_key_exists)
  private get_cached_team = AppCache.sized_cache(100, priv_get_team)
  private get_cached_name = AppCache.sized_cache(100, priv_get_name)
  private get_cached_key = AppCache.sized_cache(100, priv_get_key)
  private get_cached_path = AppCache.sized_cache(100, priv_get_path)
  private get_cached_children = AppCache.sized_cache(100, priv_get_children)
  private get_cached_children_key = AppCache.sized_cache(100, priv_get_children_key)
  private get_cached_subteams = AppCache.sized_cache(100, priv_get_all_subteams)

  /**
   * Important: for the cache invalidation to be done correctly, this function
   * must be called before any modifications are made to the team.
   */
  private function invalidate_fields(Team.key key) {
    // For get_cached_subteams, all teams in the path must be invalidated.
    // For this reason, the cache invalidation must be called BEFORE any modifications.
    // Also, this supposes that no modifications are made to the parent of the given team,
    // which is alright for now, since this is not allowed.
    path = get_path(key)
    List.iter(get_cached_subteams.invalidate, path)
    // get_cached_subteams.invalidate(key) => Included in the path.
    // Idem for children.
    parent = get_parent(key)
    Option.iter(get_cached_children.invalidate, parent)
    get_cached_children.invalidate(key)
    get_cached_children_key.invalidate(key)
    // Remaining caches.
    get_cached_team.invalidate(key)
    get_cached_path.invalidate(key)
  }
  private function invalidate_all(Team.key key) {
    get_cached_key_exists.invalidate(key)
    invalidate_fields(key)
  }

  /** Public, cached versions of the above. */

  @expand function key_exists(key) { get_cached_key_exists.get(key) }
  @expand exposed function get(key) { get_cached_team.get(key) }
  @expand function get_key(name) { get_cached_key.get(name) }
  @expand function get_name(key) { get_cached_name.get(key) }
  @expand function get_path(key) { get_cached_path.get(key) }
  @expand function get_children(key) { get_cached_children.get(key) }
  @expand function get_children_key(key) { get_cached_children_key.get(key) }
  @expand function get_all_subteams(key) { get_cached_subteams.get(key) }

  /** Other accessors. */

  function get_email(Team.key key) { Option.map(_.email, get(key)) }
  function get_by_name(string name) { Option.bind(get, get_key(name)) }
  function get_address(Team.key key) {
    match (get_email(key)) {
      case {some: email}: {internal: ~{key, email, team: true}}
      default: {unspecified: key}
    }
  }

  /** Return the sorted list / iterator of all teams. */
  function list() { iterator() |> Iter.to_list }
  function key_list() { key_iterator() |> Iter.to_list }
  function iterator() { DbSet.iterator(/webmail/teams[order +name]) }
  function key_iterator() { DbSet.iterator(/webmail/teams[order +name]/key) }
  function roots() { DbSet.iterator(/webmail/teams[parent == {none}; order +name]) |> Iter.to_list }

  /** Build the team path with either names or full values. */
  function get_name_path(Team.key key) {
    List.filter_map(get_name, get_path(key))
  }
  function get_value_path(Team.key key) {
    List.map(get, get_path(key))
  }
  function get_string_path(Team.key key) {
    get_name_path(key) |>
    List.to_string_using("/", "", "/", _)
  }

  function get_directory(Team.key key) { ?/webmail/teams[key == key]/directory }
  function get_security(Team.key key) { ?/webmail/teams[key == key]/security }
  function get_parent(Team.key key) { Option.bind(identity, ?/webmail/teams[key == key]/parent) }

  /**
   * Extract the team represented by a path.
   * @return {none} if the path is empty or cannot be identifier, else the list of the teams composing the path.
   */
  function get_from_path(list(string) path) {
    match (path) {
      case []: (none, [])
      case [root|path]:
        root = DbUtils.option(/webmail/teams[parent == none and name == root]/key)
        List.fold(function (name, (parent, path)) {
          match (parent) {
            case {some: team}:
              (DbUtils.option(/webmail/teams[parent == parent and name == name]/key), [team|path])
            default: (none, path)
          }
        }, path, (root, []))
    }

  }

  /** Count all teams. */
  function count() {
    DbSet.iterator(/webmail/teams[].{}) |> Iter.count
  }

  /** {1} Properties. */

  /**
   * Return [true] iff d0 is a descendant of d1:
   *   root/.../d1/.../d0/...
   */
  function is_subteam(Team.key d0, Team.key d1) {
    List.mem(d1, get_path(d0))
  }

  /** {1} Encryption. */

  /** Return the user public key (the function refers to the cache held in the User module). */
  @expand function publicKey(Team.key key) { User.publicKey(key) }

  /**
   * Decrypt a message using the user's secret key, and the public key of the encoder.
   * The return value will remain in Uint8Array format, since it is likely to be used
   * again in an encryption algorithm.
   */
  function decrypt(Team.key key, string message, string nonce, uint8array theirPublicKey) {
    // Fetch my secret key. WARNING: this should be the one and only db read to secret key.
    mySecretKey = ?/webmail/secretKeys[key] ? ""
    // Convert to Uint8Array.
    mySecretKey = Uint8Array.decodeBase64(mySecretKey)
    nonce = Uint8Array.decodeBase64(nonce)
    message = Uint8Array.decodeBase64(message)
    // Open the message.
    TweetNacl.Box.open(message, nonce, theirPublicKey, mySecretKey)
  }

  /** {1} Modifiers. */

  function remove(Team.key key) {
    // scan all users teams???
    match (?/webmail/teams[key == key]) {
      case {some: team}:
        invalidate_all(key) // To be done before the modifications.
        Db.remove(@/webmail/teams[key == key])
        Db.remove(@/webmail/teamkeys[team.name])
        Db.remove(@/webmail/secretKeys[key])
        Option.iter(get_cached_children.invalidate, team.parent)
        get_cached_key.invalidate(team.name)
        log("remove: {team}")
      case {none}: void
    }
  }

  /** Rename a team. Name unicity is not checked. */
  function rename(Team.key key, string previous, string new) {
    Db.remove(@/webmail/teamkeys[previous])
    /webmail/teamkeys[new] <- key
    /webmail/teams[key == key] <- {name: new, edited: Date.now()}
    get_cached_team.invalidate(key)
    get_cached_key.invalidate(previous)
  }

  /** Update all fields (again, no name unicity check). */
  function update(Team.key key, (Team.t -> Team.t) change) {
    match (?/webmail/teams[key == key]) {
      case {some: team}:
        upd = change(team)
        invalidate_fields(key) // To be done before the modifications.
        /webmail/teams[key == key] <- {upd with edited: Date.now()}
        if (upd.name != team.name) {
          Db.remove(@/webmail/teamkeys[team.name])
          /webmail/teamkeys[upd.name] <- key
          get_cached_key.invalidate(key)
        }
      case {none}: void
    }
  }

  /** Update the user count of a set of teams. */
  function register(list(Team.key) teams) {
    if (teams != []) /webmail/teams[key in teams] <- {count++}
  }
  function unregister(list(Team.key) teams) {
    if (teams != []) /webmail/teams[key in teams] <- {count--}
  }

  /** Set all the field but the key. */
  @expand function set(Team.key key, name, description) {
    update(key, function (team) { ~{team with name, description} })
  }

  /** {1} Search operators. */

  /**
   * Email address autocompletion.
   * Return the subset of the given teams matching the provded term.
   */
  function autocomplete(list(Team.key) teams, string term) {
    DbSet.iterator(/webmail/teams[key in teams and (name =~ term or email.address.local =~ term)].{email}) |>
    Iter.fold(function (team, acc) {
      elt =
        { id: Email.to_string_only_address(team.email),
          text: Email.to_string(team.email) }
      [elt|acc]
    }, _, [])
  }

  /**
   * Build the set of nodes accessible by the given user.
   * @param roots if specified, list only the roots subteams (not implemented yet).
   * @param excluded list of hidden nodes.
   * @return the serialized list of treeview nodes.
   */
  exposed function treeview(User.key key, list(string) excluded) {
    roots =
      if (User.is_super_admin(key)) roots()
      else User.get_admin_teams(key)
    List.map(buildNode(_, excluded), roots) |> List.flatten |> OpaSerialize.serialize
  }

  /** Build a treeview node. */
  protected function buildNode(Team.t team, list(string) excluded) {
    children = get_children(team.key)
    nodes = List.map(buildNode(_, excluded), children) |> List.flatten
    if (List.mem(team.key, excluded)) nodes
    else [Treeview.node(team.key, team.name, "", nodes)]
  }

}
