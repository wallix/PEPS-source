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

// This data logs individual sharings of files between users

type ShareLog.t = {
  File.id file,
  User.key sharer,
  list((User.key, FileToken.id)) shared_with,
  Date.date timestamp
}

database ShareLog.t /webmail/share_log[{file, sharer}]

module ShareLog {

  log = Log.notice("ShareLog", _)

  // Create

  function ShareLog.t make(File.id file, User.key sharer, list((User.key, FileToken.id)) shared_with) {
    ~{ file, sharer, shared_with, timestamp:Date.now() }
  }

  private function void add(ShareLog.t share_log) {
    /webmail/share_log[file == share_log.file] <- share_log
  }

  function create(File.id file, User.key sharer, list((User.key, FileToken.id)) sharees) {
    if (sharees != []) {
      log("{sharer} {@i18n("Sharing {file} with")} {String.concat(", ", List.map(_.f1, sharees))}")
      add(make(file, sharer, sharees))
    }
  }

  // Read

  function get(File.id file, User.key sharer) {
    /webmail/share_log[file == file and sharer == sharer]
  }

  function get_by_id(File.id file) {
    DbSet.iterator(/webmail/share_log[file == file])
  }

  function get_by_sharer(User.key sharer) {
    DbSet.iterator(/webmail/share_log[sharer == sharer])
  }

  function get_all() {
    DbSet.iterator(/webmail/share_log)
  }

  // It's cumulative...

  // Update

  // Delete

  // Convert

}
