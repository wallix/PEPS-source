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


package com.mlstate.webmail

Scheduler.push(function() {

  // Write DB version.
  match (DbUtils.get_version()) {
    case {some: _}: void
    default: DbUtils.set_version(AppConfig.db_version)
  }

  /**
   * Delayed startups.
   * Some of these need access to DB data etc.
   */
  Admin.init()
  App.init()
  SolrJournal.init()
  Label.init() /** Pre-created labels. */

  /** Create admin user. */
  // if (Admin.undefined())
  //   Admin.create(AppParameters.parameters.admin_pass ? "")

})
