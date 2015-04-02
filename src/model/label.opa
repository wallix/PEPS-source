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

type Label.id = int

type Label.internet = bool
type Label.team_filter = list(list(Team.key))
type Label.restriction = {
  int level,
  Label.team_filter teams,
  bool encrypt  // Activate encryption of associated messages.
}

/** Restrict selected labels. */
type Label.kind =
  {personal} or   // Only personal labels.
  {shared} or     // Personal and shared labels.
  {class} or      // Security classes.
  {all}

type Label.category =
   {personal}
or {shared}
// Following are the security labels.
or {Label.internet unprotected}
or {Label.restriction classified}
// Labels created at compile time, cannot be edited by admins.
// Can be read by any user, cannot go to the internet, no user can use them.
or {internal}


type Label.t = {
  Label.id id,
  string name,
  string description,
  User.key owner,
  Date.date created,
  option(Date.date) edited,
  option(Date.date) deleted,
  Label.category category
}

type Label.class = WBootstrap.BadgeLabel.importance

/** Safe and light label type that can be transfered to the client. */
type Label.Client.label = {
  Label.id id,
  string name,
  bool personal,
  Label.class importance,
}

type Label.filter = {string name}

type Label.autocomplete = {
  string id,
  string label,
  string value,
  string icon,
  string title,
  string cat,
  string desc
}

type Label.labels = list(Label.id)

database Label.t /webmail/labels[{id}]
database /webmail/labels[_]/category = { personal }
database /webmail/labels[_]/category/unprotected = false
database /webmail/labels[_]/category/classified full
database /webmail/labels[_]/edited = { none }
database /webmail/labels[_]/deleted = { none }

module Label {

  /** {1} Utils. */

  private function log(msg) { Log.notice("label: ", msg) }
  private function debug(msg) { Log.debug("label: ", msg) }
  // private function error(msg) { Log.error("Label: ", msg) }

  function genid() {
    gen = DbUtils.UID.gen()
    // In the event the id clashes with one used by the system.
    if (gen < 5) genid()
    else gen
  }

  function Label.id idofs(string s) { Int.of_string(s) }
  function option(Label.id) idofs_opt(string s) { Int.of_string_opt(s) }
  @stringifier(Label.id) function string sofid(Label.id id) { "{id}" }

  both emptyFilter = {name: ""}

  /**
   * {1} Generation of XIMF security labels from a classification label.
   */
  module XIMF {
    version = ("X-XIMF-Version", "1.0")
    name = ("X-XIMF-Name", "WEBMAIL PEPS DR")

    function category_to_string(category) { "" }

    private function unprotected_classification(bool internet) {[
      ("X-XIMF-Security-Classification-Identifier", "1"),
      ("X-XIMF-Security-Classification", @intl("NON PROTEGE"))] ++
      (if (internet) [("X-XIMF-Security-Categories", @intl("DIFFUSABLE PAR INTERNET"))] else [])
    }

    private function classified_classification(name) {[
      ("X-XIMF-Security-Classification-Identifier", "2"),
      ("X-XIMF-Security-Classification", @intl("DIFFUSION RESTREINTE")),
      ("X-XIMF-Security-Categories", name)
    ]}

    private function classification(message) {
      match (get(message.security)) {
        case { some: security }:
          match (security.category) {
            case { classified: _ }: classified_classification(security.name)
            case { unprotected: internet }: unprotected_classification(internet)
            default: []
          }
        default: []
      }
    }

    function make_security_label(Message.header message) {[
      ("X-XIMF-Security-Policy-Identifier", "1.2.250.1.49.3.1.0.5.100"),
      ("X-XIMF-Security-Privacy-Mark", "")] ++
      classification(message)
    }
  } // END XIMF

  /** {1} Label construction. */

  /**
   * Create a new label, without adding it to the database.
   */
  function Label.t make(User.key owner, string name, string description, Label.category category) { ~{
    id : genid(), name, description, owner, category,
    created : Date.now(), edited : none, deleted : none
  } }

  /** Insert an existent label in the database. */
  private function insert(Label.t label) {
    /webmail/labels[id == label.id] <- label
    owner = label.owner
    if (User.is_super_admin(owner))
      autocomplete_cache.reset()
    else {
      autocomplete_cache.invalidate((owner, {shared}))
      autocomplete_cache.invalidate((owner, {class}))
    }
    labelCache.invalidate(label.id)
    Sem.invalidate_label(label.id)
  }

  /** Create a new label and add it to the database. */
  function Label.t new(User.key owner, string name, string description, Label.category category) {
    label = make(owner, name, description, category)
    insert(label)
    label
  }

  /**
   * Populate the databse with a few precreated labels.
   * Those labels are immutable, with fixed IDs, and generally internal.
   * Included:
   *    - name:open, ID:1, category:{unprotected:true}
   *    - name:internal, ID:2, category:{unprotected:false}
   *    - name:attached, ID:3, category:{internal}
   *    - name:notify, ID:4, category:{internal}
   *    - name:encrypted, ID:5, category:{classified: {encrypt:true ...}}
   */
  private function system(string name, int id, Label.category category) {
    label = Label.make("SYSTEM", name, @intl("{name} label, automatically generated"), category)
    ~{label with id}
  }

  open = system("open", 1, {unprotected: true})
  internal = system("internal", 2, {unprotected: false})
  attached = system("attached", 3, {internal})
  notify = system("notify", 4, {internal})
  encrypted = system("encrypted", 5, {classified: {level: 0, teams: [], encrypt: true}})

  function init() {
    insert(open) |> ignore
    insert(internal) |> ignore
    insert(attached) |> ignore
    insert(notify) |> ignore
    insert(encrypted) |> ignore
  }

  /** The number of predefined labels. */
  predefined = 5

  /** {1} Getters. */

  /** Check existance of label id. */
  function exists(Label.id id) {
    Db.exists(@/webmail/labels[id == id].{})
  }

  /**
   * Check unicity of label name.
   * Name is unique if no label managed by the active user has the same name.
   */
  function name_exists(string name, User.key key) {
    DbSet.iterator(/webmail/labels[deleted == none and name == name and owner == key].{}) |>
    Iter.is_empty |> not
  }


  /** Return true true iff the label imposes message encryption. */
  function encryption(Label.id id) {
    category = ?/webmail/labels[id == id]/category
    match (category) {
      case {some: {classified: ~{encrypt ...}}}: encrypt
      default: false
    }
  }

  private labelCache = AppCache.sized_cache(100, function (id) {
    DbUtils.option(/webmail/labels[id == id and deleted == none])
  })

  @expand function get(Label.id id) { labelCache.get(id) }

  /** Check the ownership of the label at the same time. */
  function option(Label.t) safe_get(User.key key, Label.id id) {
    match (get(id)) {
      case { some : label }: if (label.owner == key) some(label) else none
      case { none }: none
    }
  }

  /** Extract the level or teams of a label, returing a default value if the
   * provided label is not a class.
   */
  function get_level(Label.t label) {
    match (label.category) {
      case {classified: restriction}: restriction.level
      default: 0
    }
  }
  function get_teams(Label.t label) {
    match (label.category) {
      case {classified: restriction}: List.flatten(restriction.teams)
      default: []
    }
  }

  /** {1} Modifiers. */

  /**
   * Delete a label (only changes the status, the label is still present in the Db).
   * @return [true] iff the operation was successful.
   */
  function bool delete(Label.id id) {
    @catch(function (_) { false }, {
      // PATCH: a bug in DbGen adds the field {some: date} to deleted
      // instead of replacing the old value.
      Db.remove(@/webmail/labels[id == id]/deleted)
      //
      /webmail/labels[id == id]/deleted <- {some:Date.now()}
      labelCache.invalidate(id)
      Sem.invalidate_label(id)
      true
    })
  }

  /** Remove the label from the database. */
  function void remove(Label.id id) {
    Db.remove(@/webmail/labels[id == id])
    autocomplete_cache.reset()
    labelCache.invalidate(id)
    Sem.invalidate_label(id)
  }

  /** Update a subset of the fields. */
  function set(Label.id id, name, description, category) {
    // PATCH: a bug in DbGen adds the field {some: date} to edited
    // instead of replacing the old value.
    Db.remove(@/webmail/labels[id == id]/edited)
    //
    /webmail/labels[id == id] <- ~{name, description, category, edited: {some: Date.now()}}
    labelCache.invalidate(id)
    autocomplete_cache.reset()
    Sem.invalidate_label(id)
  }

  /** {1} Querying. */

  /** Find a label by its name. */
  function find(User.key user, string name, Label.kind kind) {
    match (kind) {
      case {personal}:
        DbUtils.option(/webmail/labels[
          name == name and deleted == none and owner == user and category == {personal}
        ].{id, name, category})
      case {shared}:
        DbUtils.option(/webmail/labels[
          name == name and deleted == none and owner == user and
          ((category == {personal}) or (category == {shared}))
        ].{id, name, category})
      case {class}:
        DbUtils.option(/webmail/labels[
          name == name and deleted == none and
          ( (category.unprotected exists) or (category.classified exists) or
            (category == {internal}) )
        ].{id, name, category})
      case {all}:
        DbUtils.option(/webmail/labels[
          name == name and deleted == none and
          ( (category.unprotected exists) or (category.classified exists) or
            (category == {internal}) or (owner == user) )
        ].{id, name, category})
    }
  }

  /**
   * Return all labels usable by the active user, and belonging to a specific category.
   * @param kind kind of returned labels.
   */
  function iterator(User.key user, Label.kind kind) {
    match (kind) {
      case {personal}:
        DbSet.iterator(/webmail/labels[
          deleted == none and owner == user and category == {personal}
        ])
      case {shared}:
        DbSet.iterator(/webmail/labels[
          deleted == none and owner == user and
          ((category == {personal}) or (category == {shared}))
        ])
      case {class}:
        DbSet.iterator(/webmail/labels[
          deleted == none and
          ( (category.unprotected exists) or (category.classified exists) or
            (category == {internal}) )
        ])
      case {all}:
        DbSet.iterator(/webmail/labels[
          deleted == none and
          ( (category.unprotected exists) or (category.classified exists) or
            (category == {internal}) or (owner == user) )
        ])
    }
  }
  function list(User.key user, Label.kind kind) {
    iterator(user, kind) |> Iter.to_list
  }

  /** Return the list of labels seen by some user. */
  function list(Label.autocomplete) priv_autocomplete(User.key key, Label.kind kind) {
    match (User.get(key)) {
      case {none}: []
      case {some:user}:
        function filter(label, acc) {
          // Clearance check.
          if (Sem.user_can_use_label(user, label)) {
            auto = {
              id: "label_{label.id}",
              label: label.name,
              value: label.name,
              icon: Xhtml.to_string(category_to_icon(label)),
              title: label.name,
              cat: category_to_string(label),
              desc: category_to_descr(label)
            }
            [auto|acc]
          } else
            acc
        }
        all = iterator(key, kind)
        Iter.fold(filter, all, [])
    }
  }

  private autocomplete_cache = AppCache.sized_cache(100, function((key, kind)) { priv_autocomplete(key, kind) })
  @expand function autocomplete(User.key key, Label.kind kind) { autocomplete_cache.get((key, kind)) }

  /**
   * Fetch a specified quantity of labels matching a filter from the database.
   * The filter argument is only informative, and used to refine the db request when
   * possible, but the returned results may not pass the filter.
   */
  function fetch(User.key key, string last, int chunk, Label.filter filter, Label.kind kind) {
    match (kind) {
      case {personal}:
        DbSet.iterator(/webmail/labels[
          owner == key and deleted == {none} and name > last
          and category == {personal}; limit chunk; order +name
        ])
      case {shared}:
        DbSet.iterator(/webmail/labels[
          owner == key and deleted == {none} and name > last
          and (category == {personal} or category == {shared}); limit chunk; order +name
        ])
      // The number of security labels shouldn't be too large, so no need to refine the request any further.
      case {class}:
        DbSet.iterator(/webmail/labels[
          deleted == {none} and name > last and
          category != {shared} and category != {personal} and category != {internal};
          limit chunk; order +name
        ])
      default:
        if (filter.name == "") DbSet.iterator(/webmail/labels[name > last; limit chunk; order +name])
        else                   DbSet.iterator(/webmail/labels[name > last and name =~ filter.name; limit chunk; order +name])
    }
  }

  /** {1} Properties. */

  /** Check whether the teams of a user satisfy a team filter. */
  function check_teams(list(Team.key) ds, Label.team_filter filter) {
    if (filter == []) true
    else
      List.exists(function (conj) {
        List.for_all(function (d) { List.mem(d, ds) }, conj)
      }, filter)
  }

  /** {2} Semantics. */

  module Sem {

    /**
     * {3} Caching.
     *
     * For improved efficiency, the list of classification labels that can be read by a user is kept in a cache.
     * Checks can then be implemented as a list membership test.
     * Since the number of personal and shared labels is to be large, those are NOT included in the cache.
     */

    private function priv_readable_labels(User.key key) {
      match (User.get(key)) {
        case {some: user}:
          iterator(key, {class}) |>
          Iter.filter(user_can_read_label(user, _), _) |>
          Iter.map(_.id, _) |>
          Iter.to_list
        default:
          []
      }
    }

    private cached_readable_labels = AppCache.sized_cache(100, priv_readable_labels)

    @expand function readable_labels(User.key user) { cached_readable_labels.get(user) }

    /** Return the list of usable labels. */
    function usable_labels(User.key key, Label.kind kind) {
      match (User.get(key)) {
        case {some: user}:
          iterator(key, kind) |>
          Iter.filter(user_can_use_label(user, _), _) |>
          Iter.to_list
        default:
          []
      }
    }

    /**
     * Invalidate the cache in case a label is modified.
     * For improved efficiency, only users which could previously use the label
     * have their index invalidated.
     */
    function invalidate_label(Label.id lbl) {
      User.iterator_key() |>
      Iter.iter(function (user) {
        match (cached_readable_labels.read(user)) {
          case {some: lbls}:
            if (List.mem(lbl, lbls))
              cached_readable_labels.invalidate(user)
          default: void
        }
      }, _)
    }

    /** Invalidate a single user entry. */
    function invalidate_user(User.key user) {
      cached_readable_labels.invalidate(user)
    }


    /** Check whether a user can read a label. */
    protected function user_can_read_label(User.t user, label) {
      match (label.category) {
        case {personal}: label.owner == user.key
        case {shared}: true
        case {unprotected: _}: true
        case {classified: restriction}:
          user.level >= restriction.level &&
          check_teams(User.get_teams(user.key), restriction.teams)
        case {internal}: true
      }
    }
    protected function user_can_read_labels(User.t user, list(Label.t) labels) {
      List.for_all(user_can_read_label(user,_), labels)
    }

    /** Check whether a user can use a label. */
    protected function user_can_use_label(User.t user, Label.t label) {
      match (label.category) {
        case {personal}: label.owner == user.key
        case {shared}: label.owner == user.key
        case {unprotected: _}: true
        case {classified: restriction}:
          check_teams(User.get_teams(user.key), restriction.teams)
        case {internal}: false
      }
    }

    /** Check whether a user can edit a label. */
    protected function user_can_edit_label(User.t user, Label.t label) {
      match (label.category) {
        case {internal}: false
        default: label.owner == user.key
      }
    }

  } // END SEM

  /** Semantics when only the key is known. */
  module KeySem {
    /** Same, but the function is given the keys instead of the complete structures. */
    server function user_can_use_label(User.key key, Label.id id) {
      match (User.get(key)) {
        case {some:user}:
          match (get(id)) {
            case {some:label}: Label.Sem.user_can_use_label(user, label)
            default: false
          }
        default: false
      }
    }

    /**
     * Slightly different function that only checks security labels.
     * The result is always [false] for personal and shared labels (since it uses the
     * cache, which does not record labels other than classification ones).
     * To check personal labels (usually in the [labels] field), use the function
     * [user_can_read_label].
     */
    protected function user_can_read_security(User.key user, Label.id lbl) {
      readable = Sem.readable_labels(user)
      List.mem(lbl, readable)
    }
    protected function user_can_read_securities(User.key user, list(Label.id) lbls) {
      readable = Sem.readable_labels(user)
      List.for_all(List.mem(_, readable), lbls)
    }

    /**
     * Same, but the function is given the keys instead of the complete structures.
     */
    server function user_can_read_label(User.key key, Label.id id) {
      match (User.get(key)) {
        case {some:user}:
          match (get(id)) {
            case {some:label}: Label.Sem.user_can_read_label(user, label)
            default: false
          }
        default: false
      }
    }
    /**
     * Same, but the function is given the keys instead of the complete structures.
     */
    server function user_can_edit_label(User.key key, Label.id id) {
      match (User.get(key)) {
        case {some:user}:
          match (get(id)) {
            case {some:label}: Label.Sem.user_can_edit_label(user, label)
            default: false
          }
        default: false
      }
    }
  } // END KEYSEM


  /**
   * {2} Basic checks.
   *
   * Implement category checks, and sorting functions based on these checks.
   */

  @expand function is_personal(label) { label.category == {personal} }
  @expand function is_shared(label) { label.category == {shared} }
  @expand function allows_internet(label) { label.category == {unprotected: true} }
  @expand function is_internal(label) { label.category == {internal} }
  @expand function is_security(label) { is_security_category(label.category) }
  @expand function is_not_security(label) { not(is_security_category(label.category)) }

  /** Extract the encrypt field of a label category. */
  function encrypt(category) {
    match (category) {
      case ~{classified}: classified.encrypt
      default: false
    }
  }

  function is_unprotected(label) {
    match (label.category) {
      case { unprotected: _ }: true
      default: false
    }
  }
  function is_classified(label) {
    match (label.category) {
      case { classified: _ }: true
      default: false
    }
  }
  function is_security_category(cat) {
    match (cat) {
      case { unprotected: _ }
      case { classified: _ }
      case { internal: _ }: true
      default: false
    }
  }

  /**
   * Apply the filtering function to the given label.
   * The result is false if the label is undefined.
   */
  function bool check(Label.id id, (Label.t -> bool) filter) {
    match (get(id)) {
      case {some: label}: filter(label)
      default: false
    }
  }

  /**
   * Separate labels into shared and personal labels dependeing on their category.
   * Non existent labels are also returned as such.
   * @param check additional access check. All labels failing this check are sent to error.
   */
  function categorize(check, list(Label.id) labels) {
    init = { shared: [], personal: [], class: [], error: [] }
    List.fold(function (id, cats) {
      match (get(id)) {
        case {some: label}:
          if (check(label))
            match (label.category) {
              case {personal}: {cats with personal: [label|cats.personal]}
              case {shared}: {cats with shared: [label|cats.shared]}
              default: {cats with class: [label|cats.class]}
            }
          else {cats with error: [id|cats.error]}
        default: {cats with error: [id|cats.error]}
      }
    }, labels, init)
  }

  /** {1} Conversions. */

  exposed function category_to_icon(label) {
    match (label.category) {
      case { personal }: <span class="icon icon-locked"/>
      case { shared }: <span class="icon icon-color icon-unlocked"/>
      case { unprotected : {true} }: <span class="icon icon-green icon-unlocked"/>
      case { unprotected: {false} }: <span class="icon icon-blue icon-unlocked"/>
      case { classified: _ }: <span class="icon icon-red icon-locked"/>
      case { internal }: <span class="icon icon-red icon-locked"/>
    }
  }

  exposed function category_to_string(label) {
    match (label.category) {
      case { personal }: AppText.Personal()
      case { shared }: AppText.shared()
      case { unprotected: {true} }: AppText.Internet_diffusion()
      case { unprotected: {false} }: AppText.Not_Protected()
      case { classified: _ }: AppText.Classified_information()
      case { internal }: AppText.Internal()
    }
  }

  exposed function category_to_descr(label) {
    function no_description_if_empty(descr) {
      if (descr == "") "[{@intl("No description")}]" else descr
    }
    match (label.category) {
      case { personal }: no_description_if_empty(label.description)
      case { shared }: no_description_if_empty(label.description)
      case { unprotected: b }:
        if (b) "{AppText.Internet_allowed()}<br/></br/>{label.description}"
        else label.description
      case { classified: ~{level, teams, encrypt} }:
        "{AppText.Classified_information()}<br/><br/>{label.description}"
      case { internal }: AppText.Internal()
    }
  }

  /** Type is not imposed, importance being determined only based on the category. */
  to_importance = function {
    case { personal }: {`default`}
    case { shared }: {warning}
    case { unprotected: {true} }: {success}
    case { unprotected: {false} }: {info}
    case { classified: _ }: {important}
    case { internal }: {info}
  }

  function category(Label.id id) { Option.map(_.category, get(id)) ? {internal} }

  /** Build a user filter based the label's category. */
  function User.filter userFilter(Label.id id) {
    match (category(id)) {
      case {classified: ~{teams, level ...}}: ~{name: "", teams: List.flatten(teams), level}
      default: {name: "", teams: [], level: 0}
    }
  }

  /**
   * Convert a label to the client version.
   * The type of label is not fixed, but must define at least the fields:
   *   name, id, category
   */
  function full_to_client(label) {
    id = label.id
    name = label.name
    importance = Label.to_importance(label.category)
    // title = Label.category_to_string(label)
    ~{ id, name, importance, personal: Label.is_personal(label) }
  }

  /**
   * Extract shared or personal labels and return the matching client labels.
   * No access checks are performed, since this is not the vocation of the model.
   */
  function to_client_opt(Label.id id) {
    match (Label.get(id)) {
      case {some: label} : some(full_to_client(label))
      default: none
    }
  }

  /**
   * Same but always returns a value.
   * Default is [shared] with name [#Err] and importance [important].
   */
  function to_client(Label.id id) {
    to_client_opt(id) ? ~{id, name: "#Err", importance: {important}, personal: true}
  }

  /** Same applied to a list of labels. */
  function to_client_list(list(Label.id) labels) {
    List.filter_map(to_client_opt, labels)
  }

}

