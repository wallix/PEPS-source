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

type Directory.id = DbUtils.oid

/**
 * The same type is used for directories and shared directories. In shared directories, the
 * [clone] field is set to the original directory, and replaces the id in all queries.
 */
type Directory.t = {
  Directory.id id,
  string name,
  option(Directory.id) parent,
  option(Directory.id) clone,
  File.access access,
  User.key owner,

  option(Share.link) link,     // An optional share link.
  option(Label.id) security,   // The security label is only optional here.
  Label.labels labels,         // The same personal labels.

  Date.date created,
  option(Date.date) deleted
}

/**
 * Subset of the directory type, for partial requests.
 * Only fields relative to the file system are included: name, id, parent.
 * TODO: create minimal caching, replace requests for full directories by minimal ones
 * where ever possible.
 */
type Directory.minimal = {
  Directory.id id,
  string name,
  option(Directory.id) parent,
  option(Directory.id) clone
}

database Directory.t /webmail/directories[{id}]
database /webmail/directories[_]/deleted = none
database /webmail/directories[_]/clone = none
database /webmail/directories[_]/access = {read}

module Directory {

  /** {1} Utils. */

  private function log(msg) { Log.notice("Directory:", msg) }

  /** Abstract bypasses. */
  @expand function Directory.id idofs(string id) { DbUtils.OID.idofs(id) }
  @stringifier(Directory.id) function string sofid(Directory.id id) { DbUtils.OID.sofid(id) }

  /** {1} Creation. */

  Directory.id rootid = DbUtils.OID.idofs("Files")

  /** Build the root directory. */
  function Directory.t root(key) {
    { id: Directory.rootid,
      name: "Files", owner: key,
      parent: none, clone: none,
      access: {admin}, security: none,
      labels: [], link: none,
      created: Date.epoch, deleted: none }
  }

  /** Create a new directory, without adding it to the database. */
  function Directory.t make(User.key owner, name, option(Label.id) security, Label.labels labels, parent) { ~{
    id: DbUtils.OID.gen(),
    owner, name, parent, link: none,
    clone: none, access: {admin},
    security, labels, created: Date.now(),
    deleted: none
  } }

  /** Insert a new directory in the database. */
  private function insert(Directory.t dir) {
    /webmail/directories[id == dir.id] <- dir
    dir
  }

  /** Create a new named, rooted directory, then insert it in the database. */
  protected function create(User.key key, name, parent) {
    make(key, name, {none}, [], parent) |> insert
  }
  protected function clone(User.key key, name, parent, clone) {
    dir = make(key, name, {none}, [], parent)
    insert({ dir with clone:some(clone.dir), access: clone.access })
  }

  /** Return the directory identified by the given path, if it exists, or create it. */
  function create_from_path(User.key owner, Path.t path) {
    List.fold(function (name, parent) {
      maybe = DbSet.iterator(/webmail/directories[parent == parent and name == name and deleted == {none} and owner == owner]/id)
      match (maybe.next()) {
        case {some: (d,_)}: {some: d}
        default:
          dir = create(owner, name, parent)
          {some: dir.id}
      }
    }, path, {none})
  }

  /**
   * Initialiaze the file system of a given user by creation
   * some basic folders:
   *  - Pictures
   *  - Downloads
   *  - Documents
   *  - Shared
   */
  function init(User.key owner) {
    create_from_path(owner, [AppText.Pictures()]) |> ignore
    create_from_path(owner, [AppText.Documents()]) |> ignore
    create_from_path(owner, [AppText.Downloads()]) |> ignore
    create_from_path(owner, [AppText.shared()]) |> ignore
  }


  /** {1} Getters. */

  /** Cache declarations. */
  private minimalCache = AppCache.sized_cache(100, function (Directory.id id) {
    DbUtils.option(/webmail/directories[id == id and deleted == none].{id, name, parent, clone})
  })
  private idCache = AppCache.sized_cache(100, function ((Directory.id parent, string name)) {
    DbUtils.option(/webmail/directories[parent == some(parent) and name == name and deleted == none]/id)
  })

  @expand function getMinimal(Directory.id id) { minimalCache.get(id) }
  @expand function getId(Directory.id parent, string name) { idCache.get((parent, name)) }
  function get_name(Directory.id id) { Option.map(_.name, minimalCache.get(id)) }
  function get_parent(Directory.id id) { Option.bind(_.parent, minimalCache.get(id)) }
  function get_original(Directory.id id) { Option.bind(_.clone, minimalCache.get(id)) }

  function get(Directory.id id) {
    DbUtils.option(/webmail/directories[id == id and deleted == none])
  }
  function get_owner(Directory.id id) {
    DbUtils.option(/webmail/directories[id == id and deleted == none]/owner)
  }
  function get_security(Directory.id id) {
    DbUtils.option(/webmail/directories[id == id and deleted == none]/security) |>
    Option.bind(identity, _)
  }
  function get_labels(Directory.id id) {
    DbUtils.option(/webmail/directories[id == id and deleted == none]/labels) ? []
  }
  function get_link(Directory.id id) {
    DbUtils.option(/webmail/directories[id == id and deleted == none]/link) |>
    Option.bind(identity, _)
  }

  /** Return the owned copy of the given directory, if existing. */
  function findCopy(User.key key, Directory.id id) {
    DbUtils.option(
      /webmail/directories[
        clone == some(id) and deleted == none and
        owner == key
      ])
  }

  function exists(Directory.id id) {
    Db.exists(@/webmail/directories[id == id])
  }
  function is_shared(Directory.id id) {
    DbUtils.option(/webmail/directories[id == id and deleted == {none}]/clone) |>
    Option.bind(identity, _) |>
    Option.is_some
  }

  function has_link(Directory.t dir) { Option.is_some(dir.link) }

  function get_resource(Directory.id id) {
    parameters =
      DbUtils.option(
        /webmail/directories[id == id and deleted == none].{clone, access, owner, security})
    match (parameters) {
      case {some: partial}:
        { some:
          { owner: {key: partial.owner, isteam: Team.key_exists(partial.owner)},
            security: partial.security,
            access: partial.access,
            src: {dir: id} } }
      default: none
    }
  }

  /** {1} Queries. */

  /**
   * Return the list of user accessible directories. The conditions which define
   * the readabiliity of a file are:
   *   - user, or one of his teams, is owner of the directory.
   *   - directory has not been deleted.
   *
   * @param select which folders to select when at the root directory.
   * @param owner owner of the resource.
   * @return the list of such files, ordered by name.
   */
  protected function list(User.key owner, option(Directory.id) dir, select) {
    owners = match (select) {
      case {teams}: User.get_teams(owner)
      case {user}: [owner]
      case {all}: [owner | User.get_teams(owner)]
    }
    DbSet.iterator(/webmail/directories[
      owner in owners and parent == dir and deleted == none; order +name
    ]) |> Iter.to_list
  }

  /**
   * Generic function for building absolute paths.
   * @param transform transformation of the values: decides what to keep of the directories.
   * @param full whether to include the directory's name
   */
  private @expand protected function get_path_generic(Directory.id id, bool full, transform) {
    function drop(_, xs) { xs }
    // [app] function decides what to do with element.
    recursive function get_aux(id, app, acc) {
      match (get(id)) {
        case {none}: []
        case {some: dir}:
          match (dir.parent) {
            case {none}: app(transform(dir),acc)
            case {some:parent}: get_aux(parent, List.cons, app(transform(dir),acc))
          }
      }
    }
    if (full) get_aux(id, List.cons, [])
    else      get_aux(id, drop, [])
  }

  /**
   * Build the absolute path corresponding to the directory.
   * @param full whether to include the directory's name
   * @return a path of type Path.t
   */
  exposed function Path.t get_path(Directory.id id, bool full) {
    get_path_generic(id, full, _.name)
  }

  /**
   * Return the directories in the given directory's path.
   * @param full whether to append the current directory.
   * @return a list of directories (minimal format).
   */
  protected function get_minimal_path(Directory.id id, bool full) {
    get_path_generic(id, full, function (dir) { {name: dir.name, id: dir.id, parent: dir.parent} })
  }
  protected function get_full_path(Directory.id id, bool full) {
    get_path_generic(id, full, identity)
  }

  /**
   * Extract a directory from a parent and a subpath.
   * Three possible results:
   *   - the subpath leads to another directory => {dir}
   *   - the subpath leads to file              => {file}
   *   - the subpath is unknown                 => {inexistent}
   */
  function get_from_path(User.key owner, option(Directory.id) parent, Path.t subpath) {
    match (subpath) {
      case []: {dir: parent}
      case [name]:
        dir = DbUtils.option(/webmail/directories[owner == owner and parent == parent and name == name and deleted == {none}]/id)
        match (dir) {
          case {some: dir}: {dir: {some: dir}}
          default:
            match (FileToken.find(owner, {teams: false, location: {dir: parent}, query: ~{name}})) {
              case {some: file}: ~{file}
              default: {inexistent}
            }
        }
      case [name|subpath]:
        sub = DbUtils.option(/webmail/directories[owner == owner and parent == parent and name == name and deleted == {none}]/id)
        match (sub) {
          case {some: sub}:
            get_from_path(owner, {some: sub}, subpath)
          default: {inexistent}
        }
    }
  }


  /** Return the closest shared parent of a directory. */
  function get_shared_parent(Directory.id id) {
    match (getMinimal(id)) {
      case {some: dir}:
        match (dir.clone) {
          case {some: _}: some(dir)
          default: Option.bind(get_shared_parent, dir.parent)
        }
      default: none
    }
  }

  /** {1} Modifiers. */

  function rename(Directory.id id, string name) {
    @catch(Utils.const(false), {
      /webmail/directories[id == id] <- ~{name}
      minimalCache.invalidate(id)
      true
    })
  }

  function renameAll(list(Directory.id) ids, string name) {
    @catch(Utils.const(false), {
      /webmail/directories[id in ids] <- ~{name}
      List.iter(minimalCache.invalidate, ids)
      true
    })
  }

  function move(Directory.id id, option(Directory.id) dest) {
    @catch(Utils.const(false), {
      /webmail/directories[id == id] <- {parent: dest}
      minimalCache.invalidate(id)
      true
    })
  }

  function set_security(Directory.id id, option(Label.id) security) {
    @catch(Utils.const(false), {
      /webmail/directories[id == id]/security <- security
      true
    })
  }
  function set_labels(Directory.id id, Label.labels labels) {
    @catch(Utils.const(false), {
      /webmail/directories[id == id]/labels <- labels
      true
    })
  }
  function set_link(Directory.id id, option(Share.link) link) {
    @catch(Utils.const(false), {
      /webmail/directories[id == id]/link <- link
      true
    })
  }
  function set_clone(Directory.id id, clone) {
    @catch(Utils.const(false), {
      Db.remove(@/webmail/directories[id == id]/clone)
      /webmail/directories[id == id] <- {clone: some(clone.dir), access: clone.access}
      minimalCache.invalidate(id)
      true
    })
  }

  /**
   * Share a directory with a list of users. All contained files and directories
   * are recursively shared.
   *
   * @return the list of shared encrypted files.
   */
  function shareWith(User.key sharer, Directory.id src, list(User.key) sharees, Path.t dst, File.access access) {
    log("share_with: sharing directory {src} (at path {Path.print(dst)}) with { String.concat(",", sharees) }")

    match (get(src)) {
      case {some: dir}:
        clone =
          match (dir.clone) {
            // The directory has never been shared:
            // Perform the necessary updates to the db.
            case {none}:
              // PATCH the same as always.
              Db.remove(@/webmail/directories[id == src]/clone)
              /webmail/directories[id == src] <- {clone: some(src), access: {admin}} // Admin rights for owner.
              {dir: src, ~access}
            // Assume access rights have been checked and deemed sufficient.
            // The registered access rights are the highest of the proposed new, and the previous.
            case {some: odir}:
              {dir: odir, access: FileToken.Access.max(dir.access, access)}
          }

        // Copy the directory as needed. Created copies are gathered in order to perform
        // a joint operation for shareContent.
        outcome = List.fold(function (sharee, outcome) {
          match (outcome.status) {
            case ~{failure}: outcome
            case {success}:
              // Lookup existing clones of the directory.
              match (findCopy(sharee, clone.dir)) {
                // Update the access rights of the existing copy.
                case {some: cdir}:
                  set_clone(cdir.id, clone) |> ignore
                  outcome
                // Create a clone directory.
                default:
                  match (Directory.create_from_path(sharee, dst)) {
                    case {some: parent}:
                      copy = Directory.clone(sharee, dir.name, {some: parent}, clone)
                      {outcome with copies: [(sharee, copy.id)|outcome.copies]}
                    default:
                      copies = outcome.copies
                      msg = AppText.non_existent_folder(dst)
                      msg = if (List.length(copies) > 0) msg ^ " ({@i18n("succeeded for")} {String.concat(", ", List.map(_.f1, copies))}" else msg
                      {outcome with status: Utils.failure(msg, {wrong_address})}
                  }
              }
          }
        }, sharees, {status: {success}, copies: []})
        // Share the contents of the directory.
        match (outcome.status) {
          case {success}: {success: shareContent(sharer, src, outcome.copies, access)}
          case ~{failure}: ~{failure}
        }
        // TODO: create a sharelog for directories.
      default:
        Utils.failure(@i18n("Undefined directory {src}"), {wrong_address})
    }
  }

  /**
   * Share the content of a directories and the sub directories.
   * Special case: if the given user already has a clone of a subdirectory,
   * instead of creating a new one, the old clone is moved to the expected path.
   *
   * @param sharer owner of the original directory.
   * @param src the directory whose content to share.
   * @param copies sharees and their directory copy.
   *
   * @return the list of shared encrypted files. Each item in the list contains the encryption
   *   parameters of the token, the key and public key of the sharee, the id of its copy.
   */
  function shareContent(User.key sharer, Directory.id src, copies, File.access access) {
    // Fetch contained file tokens, and create copies for the sharee.
    files = FileToken.list(sharer, some(src), {user}, false)
    encrypted = List.fold(function (token, encrypted) {
      // Note: do NOT reuse existing tokens, since we want to have the same contents.
      // This may lead to duplicate tokens, but whatever.
      // Also FileToken.list filters out hidden files, so always hidden=false.
      match (File.get_raw_metadata(token.file)) {
        case {some: raw}:
          match ((token.encryption, raw.encryption)) {
            case ({key: fileSecretKey, ~nonce}, {key: filePublicKey ...}):
              List.fold(function ((sharee, dst), encrypted) {
                copy = FileToken.create(sharee, {shared: sharer}, token.file, raw, access, {some: dst}, false, {none}, false)
                [~{ file: copy.id, user: sharee, fileSecretKey, filePublicKey, nonce, userPublicKey: User.publicKey(sharee) } | encrypted]
              }, copies, encrypted)
            default:
              List.iter(function ((sharee, dst)) {
                FileToken.create(sharee, {shared: sharer}, token.file, raw, access, {some: dst}, false, {none}, false) |> ignore
              }, copies)
              encrypted
          }
        default: encrypted
      }
    }, files, [])

    // Fetch sub-directories, and make a recursive call to shareContent.
    subdirs = Directory.list(sharer, some(src), {all})
    List.fold(function (subdir, encrypted) {
      clone = match (subdir.clone) {
        case {none}:
          // PATCH, as always.
          Db.remove(@/webmail/directories[id == subdir.id]/clone)
          /webmail/directories[id == subdir.id] <- {clone: some(subdir.id), access: {admin}} // Admin rights for owner.
          {dir: subdir.id, ~access}
        // Assume access rights have been checked and deemed sufficient.
        case {some: odir}:
          {dir: odir, access: FileToken.Access.max(subdir.access, access)}
      }
      // First create copies of the current directory, without copying
      // the content.
      copies = List.filter_map(function ((sharee, dst)) {
        // Check for pre-existing clones.
        match (Directory.findCopy(sharee, clone.dir)) {
          // Update the access rights, and move the old clone to the expected new path.
          // If the name differ, rename to the common name.
          case {some: copy}:
            set_clone(copy.id, clone) |> ignore
            move(copy.id, {some: dst}) |> ignore
            if (copy.name != subdir.name) rename(copy.id, subdir.name) |> ignore
            none
          // Create a new clone.
          default:
            copy = Directory.clone(sharee, subdir.name, {some: dst}, clone)
            some((sharee, copy.id))
        }
      }, copies)
      // Share the content of the sub-directory, for those that did not
      // already possess a copy.
      if (copies != []) shareContent(sharer, subdir.id, copies, access) |> List.rev_append(_, encrypted)
      else encrypted
    }, subdirs, encrypted)
  }

  /**
   * Fold on the clones of a directory.
   * @param original directory over whose clones to iterate. The root directory is ignored (returns [void]).
   * @param onself the function to call when encountering the given directory.
   * @param onclones the function to call for all other clones.
   */
  function propagate(option(Directory.id) src, onself, onclones) {
    match (src) {
      case {some: src}:
        // Seek ou the clones of this directory.
        original = DbUtils.option(/webmail/directories[id == src and deleted == none]/clone) ? none
        match (original) {
          case {some: dir}:
            // Fetch clones, while separating the source version from the rest.
            (self, clones) =
              DbSet.iterator(/webmail/directories[clone == some(dir) and deleted == none]) |>
              Iter.fold(function (dir, (self, clones)) {
                if (dir.id == src) (some(dir), clones)
                else (self, [dir|clones])
              }, _, (none, []))
            // Apply {onself} to the source version
            // and onclones to the list of remaining clones.
            Option.iter(onself, self)
            onclones(clones)
          default: []
        }
      // Root directories are never shared.
      default: []
    }
  }

  /** Remove the directory, as well as all contained links. */
  function delete(User.key key, Directory.id id) {
    match (get(id)) {
      case {some: dir}:
        /webmail/directories[id == id]/deleted <- {some: Date.now()}
        minimalCache.invalidate(id)
      default: void
        /* FIXME: remove links
        // Remove self link.
        remove_link(key, dir)
        // remove all children links recursively
        fold_children(id, remove_link(key, _))
        */
    }
  }

  /** Delete a list of directories. */
  function deleteAll(list(Directory.id) ids) {
    /webmail/directories[id in ids] <- {deleted: {some: Date.now()}}
    List.iter(minimalCache.invalidate, ids)
  }

  /** Build the URN corresponding to a shared (or not) path. */
  function urn(Path.t path, option(Share.t) share) {
    match (share) {
      case {none}: {mode: {files: ""}, ~path}
      case {some: share}:
        link = "{share.link}"
        // Secret path: path of the original file.
        spath = Share.switch(share.src, FileToken.get_path, Directory.get_path(_, true))
        // Remove the secret path from the path if necessary.
        path = Utils.drop_prefix(spath, path)
        {mode: {share: link}, ~path}
    }
  }

  /** Recursively apply the given function to all the descendants of a folder. */
  private function fold(Directory.id id, (Directory.t -> void) act) {
    recursive function fold_aux(ids) {
      List.iter(function(id) {
        subdirs = DbSet.iterator(/webmail/directories[parent == {some: id} and deleted == {none}])
        res = Iter.fold(
          function(dir, acc) {
            act(dir)
            [dir.id|acc]
          }, subdirs, [])
        fold_aux(res)
      }, ids)
    }
    fold_aux([id])
  }

  // private function build_node(User.key key, Path.t path, Directory.t dir, list(string) excluded) {
  //   contents =
  //     list(key, {some: dir.id}, {all}) |>
  //     List.filter(function (dir) { not(List.mem(dir.id, excluded)) }, _)
  //   path = [dir.name|path]
  //   nodes = List.map(build_node(key, path, _, excluded), contents)
  //   // Description contains the page anchor.
  //   path = Path.print(List.rev(path))
  //   Treeview.internal(dir.id, dir.name, path, nodes)
  // }

  // /** Build the nodes matching the root folders. */
  // protected function build_root_nodes(User.key key, list(string) roots, list(string) excluded) {
  //   roots =
  //     if (roots == [])
  //       DbSet.iterator(/webmail/directories[
  //         owner == key and parent == none and
  //         deleted == none and not(id in excluded)])
  //     else
  //       DbSet.iterator(/webmail/directories[id in roots])
  //   List.map(build_node(key, [], _, excluded), Iter.to_list(roots))
  // }

  // /**
  //  * Build the nodes, and add the root directory (or 'Files' if none).
  //  * The result is serialized.
  //  */
  // exposed function build_nodes_with_root(User.key key, list(string) roots, list(string) excluded) {
  //   nodes = build_root_nodes(key, roots, excluded)
  //   if (roots == []) {
  //     root = Treeview.internal("ROOT", "Files", "", nodes)
  //     // PATCH: OpaSerialize fails the serialization of the singleton list
  //     // and returns : {hd: _, tl: []} instead of [_]
  //     "[{OpaSerialize.serialize(root)}]"
  //   } else
  //     match (nodes) {
  //       case []: "[]"
  //       case [node]: "[{OpaSerialize.serialize(node)}]"
  //       default: OpaSerialize.serialize(nodes)
  //     }
  // }

  /**
   * Build directory treeview. The treeview starts at 'Files' for user directories,
   * and 'Team' for team directories. Only accessible directories are inserted.
   * Subtrees rooted in the 'excluded' list are not added.
   */
  protected function treeview(User.key owner, list(string) excluded) {
    isteam = Team.key_exists(owner) // Teams only.
    owners = if (isteam) [owner] else [owner | User.get_teams(owner)]
    nodes =
      DbSet.iterator(/webmail/directories[
        owner in owners and parent == none and
        deleted == none and not(id in excluded)
      ]) |> Iter.to_list |>
      List.map(buildNode(owners, _, [], excluded), _)
    root = Treeview.internal("ROOT", "Files", "", nodes)
    "[{OpaSerialize.serialize(root)}]"
  }

  /** Recursively build a treeview node. */
  private function buildNode(list(User.key) owners, Directory.t parent, Path.t path, list(string) excluded) {
    contents =
      DbSet.iterator(/webmail/directories[
        owner in owners and parent == some(parent.id) and
        deleted == none and not(id in excluded)
      ]) |> Iter.to_list
    nodes = List.map(buildNode(owners, _, [parent.name|path], excluded), contents)
    path = List.rev(path) |> Path.print
    Treeview.internal(parent.id, parent.name, path, nodes)
  }

}
