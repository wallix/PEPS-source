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


package com.mlstate.webmail.static

type AppConfig.search_type = {solr} or {mongo}

module AppConfig {

  peps_dir = "/etc/peps"
  license_version = "1.0.0"


  // Dimensions of the compose window.
  // Those are set in style.less, but used to resize the modal for fullscreen mode.
  compose_width = 600
  compose_height = 400

  // Api.
  api_version = 0
  message_max_size = 16793600

  // Database.
  db_version = 1

  // Available icons.
  icons = [
    "fa-cube", "fa-bell",
    "fa-calendar", "fa-briefcase",
    "fa-comment", "fa-comments",
    "fa-browsers", "fa-camera"
  ]

  // web app domain
  default_domain = "localhost"

  function prefetch(page) { 200 }

  // is IMAP master
  is_imap_master = true

  // use security labels
  has_security_labels = true
  security_ui_type = { modern }

  // Number of list items loaded after each update of a scrolled list.
  pagesize = 50
  chooser_pagesize = 25

  default_view = {folders}

  default_notifications = true
  default_search_includes_send = true

  // Messages.
  snippet_size = 120 // Number of characters in the mail snippet.
  thumbsize = 100 // Size of image previews (square).

  admin_login = "admin"
  admin_name = @i18n("Administrator")
  admin_level = 20
  default_admin_pass = "admin"

  only_admin_can_register = true

  default_timeout = 60 // minutes
  default_grace_period = 60 // seconds

  default_level = 2


  default_backup_config = {user:"", addr:"localhost", port:22, target:"/data", schedule:120, oplog:true, enable:false}

  function level_view(level) {
    match (level) {
      case 6: @i18n("Chief")
      case 5: @i18n("Director")
      case 4: @i18n("Senior")
      case 3: @i18n("Manager")
      case 2: @i18n("Junior")
      case 1: @i18n("Intern")
      default: "{level}"
    }
  }

  // Search

  AppConfig.search_type search_type = {solr}
  int solr_journal_timer = 10*60*1000

  // Files

  default_file_chooser_page_size = 8

  // Labels

  default_label_chooser_page_size = 8

  // Users

  default_user_chooser_page_size = 8

  // Teams

  default_team_chooser_page_size = 8

  // Http server
  http_server_port = 4443

  // OAuth
  oauth_temp_token_duration_hours = 1
  oauth_token_duration_days = 365

  // Cookies
  allowed_origins = ["*"]
  auth_token = "auth_token"
  cookie_validity = 365 // (in days)
  session_cookie_validity = 3 // (in hours)

}
