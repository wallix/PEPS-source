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

/**
 * Version of the current database.
 * Needed to command migrations.
 */
database webmail { int /version }
database /webmail/version = AppConfig.db_version

/** Declaration of the database of raw data. */
database rawdata { int /version }
database /rawdata/version = AppConfig.db_version

type DbUtils.uid = int
type DbUtils.oid = string

module DbUtils {

  /** {1} Utils. */

  function log(msg) { Log.notice("DbUtils: ", msg) }
  private function debug(msg) { Log.debug("DbUtils: ", msg) }

  /** {1} Generation, parsing of OIDs. */
  module OID {
    @expand function DbUtils.oid idofs(string oid) { oid }
    @stringifier(DbUtils.oid) function string sofid(DbUtils.oid oid) { oid }

    DbUtils.oid dummy = ""

    /** Generate a unique object ID for use in the DB. */
    protected function DbUtils.oid gen() {
      MongoCommon.new_oid()
      |> Crypto.Base64.encode_compact(_)
      |> Utils.base64_url_encode
    }

    /** Generate from UID. */
    protected function DbUtils.oid genuid() {
      UID.gen() |> Int.to_hex
    }
  }

  /** {1} Generation, parsing of UIDs. */
  module UID {
    @expand function DbUtils.uid idofs(string uid) { Int.of_string(uid) }
    @stringifier(DbUtils.uid) function string sofid(DbUtils.uid uid) { "{uid}" }

    DbUtils.uid dummy = -1

    /** Generate a unique ID for use in the DB. */
    protected function DbUtils.uid gen() {
      // FIXME: we should have a safe counter instead
      Date.in_milliseconds(Date.now())
    }
  }

  /** {1} Versioning. */

  function get_version() { ?/webmail/version }
  function set_version(int version) { /webmail/version <- version }

  /** {1} Db utils. */

  /**
   * Convert a dbset to a unique option.
   */
  function uniq(x) {
    iter = DbSet.iterator(x)
    if (Iter.count(iter) == 1)
      Option.map(_.f1, iter.next())
    else
      {none}
  }

  /**
   * Convert a dbset to an option. If the function is used to extract a value
   * from an dbset built with the key as query, it is better to use this one since
   * the set can not contain more than one element.
   * @return the first element of the iteration if non empty, else [{none}].
   */
  function option(x) {
    iter = DbSet.iterator(x)
    Option.map(_.f1, iter.next())
  }

  /**
   * Fetch fixed-size pages of filtered entries from the database.
   * Most of the code is common to all uses. Specific functions include :
   *   - fecthing unfiltered chunks from the db
   *   - filtering entries
   *   - extracting information
   *
   * @param last last element of the previous page
   * @param filter element filter
   * @param ref extract an element's reference (e.g. the user name)
   * @param more request for more elements. It inputs the last element and the chunk size
   * @return a record with fields
   *     - [first], [last] first and last elements of the page)
   *     - [elts] ordered list of elements
   *     - [more] whether the db contains more elements passing the filter.
   */
  protected function get_page(last, int pagesize, filter, ref, more) {
    // Append fetched elements to the accumulator, under the given limit.
    // Returns the new accumulator, the number of added elements and the elements dropped (unfiltered).
    recursive function fold(fetched, acc, limit, nkeep, ndrop, last) {
      if (limit <= 0) (acc, nkeep, ndrop, fetched, last)
      else
        match (fetched.next()) {
          case {none}: (acc, nkeep, ndrop, Iter.empty, last)
          case {some: (elt, rem)}:
            if (filter(elt)) fold(rem, [elt|acc], limit-1, nkeep+1, ndrop, ref(elt))
            else             fold(rem, acc, limit, nkeep, ndrop+1, ref(elt))
        }
    }
    // Build the elements page.
    function make_page(first, last, elts, more, size) {
      (last, elts, size) =
        // Drop the first element, that was fetched to check for the existence
        // of the next page.
        if (more)
          match (elts) {
            case [_,e|elts]: (ref(e), [e|elts], size-1)
            default: (last, [], 0)
          }
        else (last, elts, size)
      ~{ first, last, elts, more, size }
    }
    // Repeatedly send queries until the correct amount of elements has been fetched (or none remains).
    recursive function fetch(int remains, int chunk, first, last, acc, size) {
      if (remains <= 0) make_page(first, last, acc, true, size)
      else {
        debug("Fetching {remains} (chunk:{chunk} last:{last})")
        t0 = Date.now()
        fetched = more(last, chunk)
        t1 = Date.now()
        debug("-- Db fetch delay: {Duration.between(t0, t1) |> Duration.in_milliseconds}")
        nonefetched = fetched.next() == none
        // No more elts.
        if (nonefetched) make_page(first, last, acc, false, size)
        else {
          t0 = Date.now()
          (acc, nkeep, ndrop, rem, last) = fold(fetched, acc, remains, 0, 0, last)
          t1 = Date.now()
          first = Option.map(function (t) { ref(t.f1) }, fetched.next()) ? first
          debug("-- Result fold delay: {Duration.between(t0, t1) |> Duration.in_milliseconds}")
          debug("Ratio: {nkeep}/{nkeep+ndrop} ; first:'{first}' last:'{last}'")

          // Send a new db request.
          if (nkeep + ndrop >= chunk) {
            // Empirical: new chunk size is decided upon an estimation
            // of the drop rate.
            newchunk =
              if (nkeep == 0) chunk * 2
              else (nkeep+ndrop) * (remains-nkeep) / nkeep
            // New query.
            fetch(remains-nkeep, newchunk, first, last, acc, size+nkeep)
          // If the number of fetched elements is less than the asked number, it is useless
          // to attempt a new query.
          } else
            make_page(first, last, acc, remains == nkeep, size+nkeep)
        }
      }
    }
    // Fetch the elements, plus one to check if next page exists.
    fetch(pagesize+1, pagesize+1, last, last, [], 0)
  }

}
