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

  function messages() { @intl("Messages") }
  function inbox() { @intl("Inbox") }
  function archive() { @intl("Archive") }
  function starred() { @intl("Starred") }
  function drafts() { @intl("Drafts") }
  function sent() { @intl("Sent") }
  function trash() { @intl("Trash") }
  function spam() { @intl("Spam") }

  /** Users. */

  function User() { @intl("User") }
  function users() { @intl("Users") }
  function no_users() { @intl("No users") }
  function choose_users() { @intl("Choose users") }
  function non_existent_user() { @intl("Non existent user") }
  function create_new_user() { @intl("New user") }

  /** Contacts. */

  function contact() { @intl("Contact") }
  function contacts() { @intl("Contacts") }
  function no_contacts() { @intl("No contacts") }
  function create_new_contact() { @intl("New contact") }

  /** Teams. */

  function team() { @intl("Team") }
  function teams() { @intl("Teams") }
  function no_teams() { @intl("No teams") }

  /** Files. */

  /** Directories. */

  function exists_folder(name) { @intl("The folder '{name}' already exists") }
  function non_existent_folder(Path.t p) { @intl("The folder '{Path.to_string(p)}' does not exist") }
  function no_folder_name() { @intl("No folder name provided") }
  function no_directories() { @intl("No directories") }

  /** Misc. */

  function app_title() { @intl("PEPS") }
  function app_slogan() { "" }

  function dashboard() { @intl("Dashboard") }
  function settings() { @intl("Settings") }
  function password() { @intl("Password") }
  function login() { @intl("Login") }
  function Login_please() { @intl("Login please") }
  function email() { @intl("Email") }
  function emails() { @intl("Emails") }
  function history() { @intl("History") }
  function compose() { @intl("Compose") }



  function people() { @intl("People") }
  function search() { @intl("Search") }
  function classification() { @intl("Classification") }
  function Label() { @intl("Label") }
  function labels() { @intl("Labels") }
  function Folder() { @intl("Folder") }
  function folders() { @intl("Folders") }
  function admin() { @intl("Admin") }
  function files() { @intl("Files") }
  function File() { @intl("File") }
  function Directory() { @intl("Directory") }
  function no_files() { @intl("No files") }
  function no_labels() { @intl("No labels") }
  function attach() { @intl("Attach") }
  function select() { @intl("Select") }
  function Update() { @intl("Update") }
  function Updating() { @intl("Updating...") }
  function action() { @intl("Action") }
  function attachment() { @intl("attachment") }
  function attachments() { @intl("attachments") }
  function Attachments() { @intl("Attachments") }
  function new_message() { @intl("New message") }
  function choose_file() { @intl("Choose file") }
  function choose_folder() { @intl("Choose folder") }
  function choose_file_or_folder() { @intl("Choose file or folder") }
  function choose_from_files() { @intl("Choose from files") }
  function choose_labels() { @intl("Choose labels") }
  function choose_classifications() { @intl("Choose classifications") }
  function choose_labels_or_classifications() { @intl("Choose labels or classifications") }
  function choose_teams() { @intl("Choose teams") }
  function filter() { @intl("Filter") }
  function description() { @intl("Description") }
  function Team_Folders() { @intl("Team Folders") }
  function upload_file() { @intl("Upload file") }
  function share_file() { @intl("Share file") }
  function edit_message() { @intl("Edit message") }
  function reedit_message() { @intl("Re-edit message") }
  function refresh() { @intl("Refresh") }
  function empty_trash() { @intl("Empty trash") }
  function reply_message() { @intl("Reply message") }
  function forward_message() { @intl("Forward message") }
  function not_allowed_message() { @intl("You are not allowed to view this message") }
  function missing_file(file) { @intl("Missing file '{file}'") }
  function missing_user(users) {
    match (users) {
    case []: @intl("No missing users")
    case [user]: @intl("Missing user '{user}'")
    default: @intl("Missing users {String.concat(", ",users)}")
    }
  }
  function error() { @intl("Error") }
  function Not_Allowed() { @intl("Not Allowed") }
  function Failed() { @intl("Failed") }
  function Non_existent_message() { @intl("Non-existent message") }
  function Non_existent_user() { @intl("Non-existent user") }
  function Message_not_found() { @intl("Message not found") }
  function Warning() { @intl("Warning") }
  function Not_found() { @intl("Not found") }
  function Bad_request() { @intl("Bad request") }
  function Internal_Error() { @intl("Internal Error") }
  function Removed() { @intl("Removed") }
  function Done() { @intl("Done") }
  function Indexing() { @intl("Indexing") }
  function Logging() { @intl("Logging") }
  function Backup() { @intl("Backup") }
  function Save_failure() { @intl("Save failure") }
  function Cancel() { @intl("Cancel") }
  function Personal() { @intl("Personal") }
  function Profile() { @intl("Profile") }
  function Options() { @intl("Options") }
  function Signature() { @intl("Signature") }
  function Display() { @intl("Display") }
  function Enabled() { @intl("Enabled") }
  function Disabled() { @intl("Disabled") }
  function Refresh() { @intl("Refresh") }
  function Documents() { @intl("Documents") }
  function Downloads() { @intl("Downloads") }
  function Pictures() { @intl("Pictures") }
  function Recent_files() { @intl("Recent files") }
  function Select_file() { @intl("Select file") }
  function Send_failure() { @intl("Send failure") }
  function Reply_failure() { @intl("Reply failure") }
  function Move_failure() { @intl("Move failure") }
  function Deletion_failure() { @intl("Deletion failure") }
  function Reply() { @intl("Reply") }
  function Reply_All() { @intl("Reply All") }
  function Reedit() { @intl("Re-edit") }
  function Quick_Reply() { @intl("Quick Reply") }
  function Edit() { @intl("Edit") }
  function Forward() { @intl("Forward") }
  function From() { @intl("From") }
  function To() { @intl("To") }
  function Cc() { @intl("Cc") }
  function Bcc() { @intl("Bcc") }
  function Date() { @intl("Date") }
  function Subject() { @intl("Subject") }
  function Newer() { @intl("Newer") }
  function Older() { @intl("Older") }
  function Re() { @intl("Re") }
  function Fwd() { @intl("Fwd") }
  function Block() { @intl("Block") }
  function Unblock() { @intl("Unblock") }
  function Blocking() { @intl("Blocking...") }
  function Unblocking() { @intl("Unblocking...") }
  function Blocked() { @intl("Blocked") }
  function Ok() { @intl("Ok") }
  function lock() { @intl("lock") }
  function unlock() { @intl("unlock") }
  function Lock() { @intl("Lock") }
  function Unlock() { @intl("Unlock") }
  function Unlocking() { @intl("Unlocking...") }
  function Admin() { @intl("Admin") }
  function Super_Admin() { @intl("Super Admin") }
  function Draft_not_found() { @intl("Draft not found") }
  function Category() { @intl("Category") }
  function Publish() { @intl("Publish") }
  function Onboarding() { @intl("Onboarding") }
  function Apps() { @intl("Apps") }
  function Key() { @intl("Key") }
  function Certificate() { @intl("Certificate") }
  function Keys() { @intl("Keys") }
  function Secret() { @intl("Secret") }
  function Id() { @intl("Id") }
  function Provider() { @intl("Provider") }
  function No_apps() { @intl("No apps") }
  function Create_app() { @intl("Create app") }
  function Create_key() { @intl("Create key") }

  // Label

  function create_label() { @intl("Create label") }
  function edit_label(name) { @intl("Edit label : {name}") }
  function create_new_label() { @intl("New label") }
  function invalid_labels(list(string) labels) { @intl("Labels not valid for user: [{String.concat(", ",labels)}]") }
  function missing_label(string name) { @intl("Missing label '{name}'") }
  function missing_label_id(int id) { @intl("Missing label id '{id}'") }

  // Team

  function create_team() { @intl("Create team") }
  function edit_team(name) { @intl("Edit team : {name}") }
  function create_new_team() { @intl("New team") }

  // Register

  function Sign_in() { @intl("Sign in") }
  function sign_in_to_mailbox() { @intl("Sign in to your account") }
  function register() { @intl("Register") }
  function register_new_account() { @intl("Create a new account") }

  function not_allowed_resource() { @intl("You are not allowed to view this resource") }
  function not_allowed_action() { @intl("You are not allowed to do this action") }
  function not_allowed_download() { @intl("You are not allowed to download this file") }
  function inexistent_resource() { @intl("The requested resource does not exist") }
  function login_please() { @intl("Log-in please") }
  function invalid_request() { @intl("Invalid request") }
  function inexistent_user() { @intl("This user does not exist") }
  function not_multipart() { @intl("The message you are uploading is not multipart") }
  function bad_parameter() { @intl("Bad parameter(s) in request") }

  // Settings

  function parameters() { @intl("Parameters") }
  function certificates() { @intl("Certificates") }
  function status() { @intl("Status") }
  function running() { @intl("Running") }
  function stopped() { @intl("Stopped") }
  function check() { @intl("Check") }
  function checking() { @intl("Checking...") }
  function restart() { @intl("Restart") }
  function restarting() { @intl("Restarting...") }
  function save() { @intl("Save") }
  function saving() { @intl("Saving") }
  function reset() { @intl("Reset") }
  function reseting() { @intl("Reseting") }
  function removing() { @intl("Removing") }
  function backup_now() { @intl("Backup now") }
  function backing_up() { @intl("Backing up") }
  function create() { @intl("Create") }
  function creating() { @intl("Creating") }


  // File
  function name() { @intl("Name") }
  function level() { @intl("Level") }
  function size() { @intl("Size") }
  function kind() { @intl("Kind") }
  function modified() { @intl("Modified") }
  function inexistent_file() { @intl("File not found") }
  function download() { @intl("Download") }
  function hide() { @intl("Hide") }
  function move() { @intl("Move") }
  function security() { @intl("Security") }
  function created() { @intl("Created") }
  function change_classification() { @intl("Change classification") }

  function link() { @intl("Link") }
  function links() { @intl("Links") }
  function view_links() { @intl("View links") }

  function shared() { @intl("Shared") }
  function Deleting() { @intl("Deleting") }
  function Deleted() { @intl("Deleted") }
  function shared_by() { @intl("Shared by") }
  function owner() { @intl("Owner") }
  function no_links() { @intl("No links for the moment") }
  function actions() { @intl("Actions") }
  function path() { @intl("Path") }
  function Internet_diffusion() { @intl("Internet diffusion") }
  function Internet_allowed() { @intl("Internet allowed") }
  function Restricted_diffusion() { @intl("Restricted diffusion") }
  function Not_Protected() { @intl("Not Protected") }
  function Classified_information() { @intl("Classified information") }
  function Internal() { @intl("Internal") }
  function Label_not_found() { @intl("Label not found") }

  function create_folder() { @intl("Create folder") }
  function edit_folder(name) { @intl("Edit folder : {name}") }
  function create_new_folder() { @intl("Create a new folder") }
  function empty_folder() { @intl("This folder is empty") }
  function Folder_does_not_exist() { @intl("Folder does not exist") }
  function no_file_name() { @intl("No file name provided") }
  function no_contact_name() { @intl("No contact name provided") }
  function no_destination() { @intl("No destination provided") }
  function rename() { @intl("Rename") }
  function delete() { @intl("Delete") }
  function share() { @intl("Share") }
  function create_link() { @intl("Create link") }
  function share_link() { @intl("Share link") }
  function share_with() { @intl("Share with") }
  function unshare_link() { @intl("Remove link") }
  function show_in_my_files() { @intl("Show in My Files") }
  function no_files_provided() { @intl("No files provided") }

  function inexistent_link() { @intl("Link not found") }
  function unauthorized() { @intl("Unauthorized") }

  function home() { @intl("Home") }
  function upload() { @intl("Upload") }
  function Uploading() { @intl("Uploading...") }
  function Uploaded() { @intl("Uploaded") }
  function new_folder() { @intl("New folder") }
  function upload_help() { @intl("You can select more than one file at a time or drag and drop files anywhere on this box to start uploading.") }
  function reindex_help() { @intl("Reindexing can take a long time depending upon your data size.") }
  function reindex_help_small() { @intl("You should ensure that as little activity as possible is present on your PEPS server during these operations.") }

  function user_not_found() { @intl("User not found") }

  function invalid_username_password() { @intl("Invalid username or password") }
  function Invalid_password() { @intl("Invalid password") }
  function Insufficient_clearance() { @intl("Insufficient clearance") }
  function Send() { @intl("Send") }
  function Sending() { @intl("Sending...") }
  function Sent() { @intl("Sent") }
  function remove() { @intl("Remove") }

  function encryption() { @intl("Encryption") }
  function allow_internet() { @intl("Allow internet diffusion") }

  mlstate_url = "http://mlstate.com"
  function copyright() {
    <></>
    // <>{@intl("Copyright")} © 2010-2014 {Utils.make_ext_link_w_title(mlstate_url, @intl("Visit the MLstate website"), <>MLstate</>)}</>
  }
  opalang_url = "http://opalang.org"
  function extra_footer() {
    <></>
    // <> &#9679; {@intl("Built with")} {Utils.make_ext_link_w_title(opalang_url, @intl("Visit the Opa website"), <>Opa</>)}</>
  }

  function new_mails_title() { @intl("New mails") }
  function loading_title() { @intl("Loading") }

  client function print_wrote(date, from, content, sgn) { @intl("

{sgn}
On {date}, {from} wrote :
{Utils.print_reply(content)}")
  }

  function session_expired() { @intl("Session expired") }
  function logout_confirm() { @intl("Do you wish to logout?") }
  function logout_timer(time) { @intl("Logout automatically in {time} seconds") }

  function yes() { @intl("Yes") }
  function no() { @intl("No") }
  function new() { @intl("New") }
  function success() { @intl("success") }
  function failure() { @intl("failure") }
  function Success() { @intl("Success") }
  function Failure() { @intl("Failure") }
  function Logout() { @intl("Logout") }

}
