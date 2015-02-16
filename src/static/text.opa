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

module AppText {

  /** Messages. */

  function messages() { @i18n("Messages") }
  function inbox() { @i18n("Inbox") }
  function archive() { @i18n("Archive") }
  function starred() { @i18n("Starred") }
  function drafts() { @i18n("Drafts") }
  function sent() { @i18n("Sent") }
  function trash() { @i18n("Trash") }
  function spam() { @i18n("Spam") }

  /** Users. */

  function User() { @i18n("User") }
  function users() { @i18n("Users") }
  function no_users() { @i18n("No users") }
  function choose_users() { @i18n("Choose users") }
  function non_existent_user() { @i18n("Non existent user") }
  function create_new_user() { @i18n("New user") }

  /** Contacts. */

  function contact() { @i18n("Contact") }
  function contacts() { @i18n("Contacts") }
  function no_contacts() { @i18n("No contacts") }
  function create_new_contact() { @i18n("New contact") }

  /** Teams. */

  function team() { @i18n("Team") }
  function teams() { @i18n("Teams") }
  function no_teams() { @i18n("No teams") }

  /** Files. */

  /** Directories. */

  function exists_folder(name) { @i18n("The folder '{name}' already exists") }
  function non_existent_folder(Path.t p) { @i18n("The folder '{Path.to_string(p)}' does not exist") }
  function no_folder_name() { @i18n("No folder name provided") }
  function no_directories() { @i18n("No directories") }

  /** Misc. */

  function app_title() { @i18n("PEPS") }
  function app_slogan() { "" }

  function dashboard() { @i18n("Dashboard") }
  function settings() { @i18n("Settings") }
  function password() { @i18n("Password") }
  function login() { @i18n("Login") }
  function Login_please() { @i18n("Login please") }
  function email() { @i18n("Email") }
  function emails() { @i18n("Emails") }
  function history() { @i18n("History") }
  function compose() { @i18n("Compose") }



  function people() { @i18n("People") }
  function search() { @i18n("Search") }
  function classification() { @i18n("Classification") }
  function Label() { @i18n("Label") }
  function labels() { @i18n("Labels") }
  function Folder() { @i18n("Folder") }
  function folders() { @i18n("Folders") }
  function admin() { @i18n("Admin") }
  function files() { @i18n("Files") }
  function File() { @i18n("File") }
  function Directory() { @i18n("Directory") }
  function no_files() { @i18n("No files") }
  function no_labels() { @i18n("No labels") }
  function attach() { @i18n("Attach") }
  function select() { @i18n("Select") }
  function Update() { @i18n("Update") }
  function Updating() { @i18n("Updating...") }
  function action() { @i18n("Action") }
  function attachment() { @i18n("attachment") }
  function attachments() { @i18n("attachments") }
  function Attachments() { @i18n("Attachments") }
  function new_message() { @i18n("New message") }
  function choose_file() { @i18n("Choose file") }
  function choose_folder() { @i18n("Choose folder") }
  function choose_file_or_folder() { @i18n("Choose file or folder") }
  function choose_from_files() { @i18n("Choose from files") }
  function choose_labels() { @i18n("Choose labels") }
  function choose_classifications() { @i18n("Choose classifications") }
  function choose_labels_or_classifications() { @i18n("Choose labels or classifications") }
  function choose_teams() { @i18n("Choose teams") }
  function filter() { @i18n("Filter") }
  function description() { @i18n("Description") }
  function Team_Folders() { @i18n("Team Folders") }
  function upload_file() { @i18n("Upload file") }
  function share_file() { @i18n("Share file") }
  function edit_message() { @i18n("Edit message") }
  function reedit_message() { @i18n("Re-edit message") }
  function refresh() { @i18n("Refresh") }
  function empty_trash() { @i18n("Empty trash") }
  function reply_message() { @i18n("Reply message") }
  function forward_message() { @i18n("Forward message") }
  function not_allowed_message() { @i18n("You are not allowed to view this message") }
  function missing_file(file) { @i18n("Missing file '{file}'") }
  function missing_user(users) {
    match (users) {
    case []: @i18n("No missing users")
    case [user]: @i18n("Missing user '{user}'")
    default: @i18n("Missing users {String.concat(", ",users)}")
    }
  }
  function error() { @i18n("Error") }
  function Not_Allowed() { @i18n("Not Allowed") }
  function Failed() { @i18n("Failed") }
  function Non_existent_message() { @i18n("Non-existent message") }
  function Non_existent_user() { @i18n("Non-existent user") }
  function Message_not_found() { @i18n("Message not found") }
  function Warning() { @i18n("Warning") }
  function Not_found() { @i18n("Not found") }
  function Bad_request() { @i18n("Bad request") }
  function Internal_Error() { @i18n("Internal Error") }
  function Removed() { @i18n("Removed") }
  function Done() { @i18n("Done") }
  function Indexing() { @i18n("Indexing") }
  function Logging() { @i18n("Logging") }
  function Backup() { @i18n("Backup") }
  function Save_failure() { @i18n("Save failure") }
  function Cancel() { @i18n("Cancel") }
  function Personal() { @i18n("Personal") }
  function Profile() { @i18n("Profile") }
  function Options() { @i18n("Options") }
  function Signature() { @i18n("Signature") }
  function Display() { @i18n("Display") }
  function Enabled() { @i18n("Enabled") }
  function Disabled() { @i18n("Disabled") }
  function Refresh() { @i18n("Refresh") }
  function Documents() { @i18n("Documents") }
  function Downloads() { @i18n("Downloads") }
  function Pictures() { @i18n("Pictures") }
  function Recent_files() { @i18n("Recent files") }
  function Select_file() { @i18n("Select file") }
  function Send_failure() { @i18n("Send failure") }
  function Reply_failure() { @i18n("Reply failure") }
  function Move_failure() { @i18n("Move failure") }
  function Deletion_failure() { @i18n("Deletion failure") }
  function Reply() { @i18n("Reply") }
  function Reply_All() { @i18n("Reply All") }
  function Reedit() { @i18n("Re-edit") }
  function Quick_Reply() { @i18n("Quick Reply") }
  function Edit() { @i18n("Edit") }
  function Forward() { @i18n("Forward") }
  function From() { @i18n("From") }
  function To() { @i18n("To") }
  function Cc() { @i18n("Cc") }
  function Bcc() { @i18n("Bcc") }
  function Date() { @i18n("Date") }
  function Subject() { @i18n("Subject") }
  function Newer() { @i18n("Newer") }
  function Older() { @i18n("Older") }
  function Re() { @i18n("Re") }
  function Fwd() { @i18n("Fwd") }
  function Block() { @i18n("Block") }
  function Unblock() { @i18n("Unblock") }
  function Blocking() { @i18n("Blocking...") }
  function Unblocking() { @i18n("Unblocking...") }
  function Blocked() { @i18n("Blocked") }
  function Ok() { @i18n("Ok") }
  function lock() { @i18n("lock") }
  function unlock() { @i18n("unlock") }
  function Lock() { @i18n("Lock") }
  function Unlock() { @i18n("Unlock") }
  function Unlocking() { @i18n("Unlocking...") }
  function Admin() { @i18n("Admin") }
  function Super_Admin() { @i18n("Super Admin") }
  function Draft_not_found() { @i18n("Draft not found") }
  function Category() { @i18n("Category") }
  function Publish() { @i18n("Publish") }
  function Onboarding() { @i18n("Onboarding") }
  function Apps() { @i18n("Apps") }
  function Key() { @i18n("Key") }
  function Certificate() { @i18n("Certificate") }
  function Keys() { @i18n("Keys") }
  function Secret() { @i18n("Secret") }
  function Id() { @i18n("Id") }
  function Provider() { @i18n("Provider") }
  function No_apps() { @i18n("No apps") }
  function Create_app() { @i18n("Create app") }
  function Create_key() { @i18n("Create key") }

  // Label

  function create_label() { @i18n("Create label") }
  function edit_label(name) { @i18n("Edit label : {name}") }
  function create_new_label() { @i18n("New label") }
  function invalid_labels(list(string) labels) { @i18n("Labels not valid for user: [{String.concat(", ",labels)}]") }
  function missing_label(string name) { @i18n("Missing label '{name}'") }
  function missing_label_id(int id) { @i18n("Missing label id '{id}'") }

  // Team

  function create_team() { @i18n("Create team") }
  function edit_team(name) { @i18n("Edit team : {name}") }
  function create_new_team() { @i18n("New team") }

  // Register

  function Sign_in() { @i18n("Sign in") }
  function sign_in_to_mailbox() { @i18n("Sign in to your account") }
  function register() { @i18n("Register") }
  function register_new_account() { @i18n("Create a new account") }

  function not_allowed_resource() { @i18n("You are not allowed to view this resource") }
  function not_allowed_action() { @i18n("You are not allowed to do this action") }
  function not_allowed_download() { @i18n("You are not allowed to download this file") }
  function inexistent_resource() { @i18n("The requested resource does not exist") }
  function login_please() { @i18n("Log-in please") }
  function invalid_request() { @i18n("Invalid request") }
  function inexistent_user() { @i18n("This user does not exist") }
  function not_multipart() { @i18n("The message you are uploading is not multipart") }
  function bad_parameter() { @i18n("Bad parameter(s) in request") }

  // Settings

  function parameters() { @i18n("Parameters") }
  function certificates() { @i18n("Certificates") }
  function status() { @i18n("Status") }
  function running() { @i18n("Running") }
  function stopped() { @i18n("Stopped") }
  function check() { @i18n("Check") }
  function checking() { @i18n("Checking...") }
  function restart() { @i18n("Restart") }
  function restarting() { @i18n("Restarting...") }
  function save() { @i18n("Save") }
  function saving() { @i18n("Saving") }
  function reset() { @i18n("Reset") }
  function reseting() { @i18n("Reseting") }
  function removing() { @i18n("Removing") }
  function backup_now() { @i18n("Backup now") }
  function backing_up() { @i18n("Backing up") }
  function create() { @i18n("Create") }
  function creating() { @i18n("Creating") }


  // File
  function name() { @i18n("Name") }
  function level() { @i18n("Level") }
  function size() { @i18n("Size") }
  function kind() { @i18n("Kind") }
  function modified() { @i18n("Modified") }
  function inexistent_file() { @i18n("File not found") }
  function download() { @i18n("Download") }
  function hide() { @i18n("Hide") }
  function move() { @i18n("Move") }
  function security() { @i18n("Security") }
  function created() { @i18n("Created") }
  function change_classification() { @i18n("Change classification") }

  function link() { @i18n("Link") }
  function links() { @i18n("Links") }
  function view_links() { @i18n("View links") }

  function shared() { @i18n("Shared") }
  function Deleting() { @i18n("Deleting") }
  function Deleted() { @i18n("Deleted") }
  function shared_by() { @i18n("Shared by") }
  function owner() { @i18n("Owner") }
  function no_links() { @i18n("No links for the moment") }
  function actions() { @i18n("Actions") }
  function path() { @i18n("Path") }
  function Internet_diffusion() { @i18n("Internet diffusion") }
  function Internet_allowed() { @i18n("Internet allowed") }
  function Restricted_diffusion() { @i18n("Restricted diffusion") }
  function Not_Protected() { @i18n("Not Protected") }
  function Classified_information() { @i18n("Classified information") }
  function Internal() { @i18n("Internal") }
  function Label_not_found() { @i18n("Label not found") }

  function create_folder() { @i18n("Create folder") }
  function edit_folder(name) { @i18n("Edit folder : {name}") }
  function create_new_folder() { @i18n("Create a new folder") }
  function empty_folder() { @i18n("This folder is empty") }
  function Folder_does_not_exist() { @i18n("Folder does not exist") }
  function no_file_name() { @i18n("No file name provided") }
  function no_contact_name() { @i18n("No contact name provided") }
  function no_destination() { @i18n("No destination provided") }
  function rename() { @i18n("Rename") }
  function delete() { @i18n("Delete") }
  function share() { @i18n("Share") }
  function create_link() { @i18n("Create link") }
  function share_link() { @i18n("Share link") }
  function share_with() { @i18n("Share with") }
  function unshare_link() { @i18n("Remove link") }
  function show_in_my_files() { @i18n("Show in My Files") }
  function no_files_provided() { @i18n("No files provided") }

  function inexistent_link() { @i18n("Link not found") }
  function unauthorized() { @i18n("Unauthorized") }

  function home() { @i18n("Home") }
  function upload() { @i18n("Upload") }
  function Uploading() { @i18n("Uploading...") }
  function Uploaded() { @i18n("Uploaded") }
  function new_folder() { @i18n("New folder") }
  function upload_help() { @i18n("You can select more than one file at a time or drag and drop files anywhere on this box to start uploading.") }
  function reindex_help() { @i18n("Reindexing can take a long time depending upon your data size.") }
  function reindex_help_small() { @i18n("You should ensure that as little activity as possible is present on your PEPS server during these operations.") }

  function user_not_found() { @i18n("User not found") }

  function invalid_username_password() { @i18n("Invalid username or password") }
  function Invalid_password() { @i18n("Invalid password") }
  function Insufficient_clearance() { @i18n("Insufficient clearance") }
  function Send() { @i18n("Send") }
  function Sending() { @i18n("Sending...") }
  function Sent() { @i18n("Sent") }
  function remove() { @i18n("Remove") }

  function encryption() { @i18n("Encryption") }
  function allow_internet() { @i18n("Allow internet diffusion") }

  mlstate_url = "http://mlstate.com"
  function copyright() {
    <></>
    // <>{@i18n("Copyright")} © 2010-2014 {Utils.make_ext_link_w_title(mlstate_url, @i18n("Visit the MLstate website"), <>MLstate</>)}</>
  }
  opalang_url = "http://opalang.org"
  function extra_footer() {
    <></>
    // <> &#9679; {@i18n("Built with")} {Utils.make_ext_link_w_title(opalang_url, @i18n("Visit the Opa website"), <>Opa</>)}</>
  }

  function new_mails_title() { @i18n("New mails") }
  function loading_title() { @i18n("Loading") }

  function print_wrote(date, from, content, sgn) { @i18n("

{sgn}
On {date}, {from} wrote :
{Utils.print_reply(content)}")
  }

  function session_expired() { @i18n("Session expired") }
  function logout_confirm() { @i18n("Do you wish to logout?") }
  function logout_timer(time) { @i18n("Logout automatically in {time} seconds") }

  function yes() { @i18n("Yes") }
  function no() { @i18n("No") }
  function new() { @i18n("New") }
  function success() { @i18n("success") }
  function failure() { @i18n("failure") }
  function Success() { @i18n("Success") }
  function Failure() { @i18n("Failure") }
  function Logout() { @i18n("Logout") }

}
