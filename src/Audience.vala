// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/*-
 * Copyright (c) 2013-2014 Audience Developers (http://launchpad.net/pantheon-chat)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 *
 * Authored by: Tom Beckmann <tomjonabc@gmail.com>
 *              Cody Garver <cody@elementaryos.org>
 *              Artem Anufrij <artem.anufrij@live.de>
 */

/*
[CCode (cname="gst_navigation_query_parse_commands_length")]
public extern bool gst_navigation_query_parse_commands_length (Gst.Query q, out uint n);
[CCode (cname="gst_navigation_query_parse_commands_nth")]
public extern bool gst_navigation_query_parse_commands_nth (Gst.Query q, uint n, out Gst.NavigationCommand cmd);
*/
namespace Audience {
    public enum Page {
        WELCOME,
        PLAYER
    }

    public Audience.Settings settings; //global space for easier access...

    public class App : Granite.Application {

        /**
         * Translatable launcher (.desktop) strings to be added to template (.pot) file.
         * These strings should reflect any changes in these launcher keys in .desktop file
         */
        /// TRANSLATORS: This is the name of the application shown in the application launcher. Some distributors (e.g. elementary OS) choose to display it instead of the brand name "Audience".
        public const string VIDEOS = N_("Videos");
        /// TRANSLATORS: These are the keywords used when searching for this application in an application store or launcher.
        public const string KEYWORDS = N_("Audience;Video;Player;Movies;");
        public const string COMMENT = N_("Watch videos and movies");
        public const string GENERIC_NAME = N_("Video Player");
        /// TRANSLATORS: This is the shortcut used to view information about the application itself when its displayed name is branded "Audience".
        public const string ABOUT_STOCK = N_("About Audience");
        /// TRANSLATORS: This is the shortcut used to view information about the application itself when its displayed name is the localized equivalent of "Videos".
        public const string ABOUT_GENERIC = N_("About Videos");

        construct {
            program_name = "Audience";
            exec_name = "audience";

            build_data_dir = Constants.DATADIR;
            build_pkg_data_dir = Constants.PKGDATADIR;
            build_release_name = Constants.RELEASE_NAME;
            build_version = Constants.VERSION;
            build_version_info = Constants.VERSION_INFO;

            app_years = "2011-2015";
            app_icon = "audience";
            app_launcher = "audience.desktop";
            application_id = "net.launchpad.audience";

            main_url = "https://code.launchpad.net/audience";
            bug_url = "https://bugs.launchpad.net/audience";
            help_url = "https://code.launchpad.net/audience";
            translate_url = "https://translations.launchpad.net/audience";

            about_authors = { "Cody Garver <cody@elementaryos.org>",
                              "Tom Beckmann <tom@elementaryos.org>" };
            /*about_documenters = {""};
            about_artists = {""};
            about_translators = "Launchpad Translators";
            about_comments = "To be determined"; */
            about_license_type = Gtk.License.GPL_3_0;
        }

        public Gtk.Window     mainwindow;
        private Gtk.HeaderBar header;

        private Page _page;
        public Page page {
            get {
                return _page;
            }
            set {
                switch (value) {
                    case Page.PLAYER:
                        if (page == Page.PLAYER)
                            break;

                        if (mainwindow.get_child()!=null)
                            mainwindow.get_child().destroy ();

                        var new_widget = new PlayerPage ();
                        new_widget.ended.connect (on_player_ended);
                        mainwindow.add (new_widget);
                        mainwindow.show_all ();

                        _page = Page.PLAYER;
                        break;
                    case Page.WELCOME:
                        var pl = mainwindow.get_child () as PlayerPage;
                        if (pl!=null) {
                            pl.ended.disconnect (on_player_ended);
                            pl.destroy ();
                        }

                        var new_widget = new WelcomePage ();
                        mainwindow.add (new_widget);
                        mainwindow.show_all ();

                        _page = Page.WELCOME;
                        break;
                }
            }
        }

        private static App app; // global App instance
        public DiskManager disk_manager;

        public GLib.VolumeMonitor monitor;

        public signal void media_volumes_changed ();

        public App () {
            Granite.Services.Logger.DisplayLevel = Granite.Services.LogLevel.DEBUG;

            Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = true;
            this.flags |= GLib.ApplicationFlags.HANDLES_OPEN;

        }

        public static App get_instance () {
            if (app == null)
                app = new App ();
            return app;
        }

        void build () {
            settings = new Settings ();
            mainwindow = new Gtk.Window ();

            if (settings.last_folder == "-1")
                settings.last_folder = Environment.get_home_dir ();

            header = new Gtk.HeaderBar ();
            header.set_show_close_button (true);
            header.get_style_context ().remove_class ("header-bar");

            disk_manager = DiskManager.get_default ();

            disk_manager.volume_found.connect ((vol) => {
                media_volumes_changed ();
            });

            disk_manager.volume_removed.connect ((vol) => {
                media_volumes_changed ();
            });

            page = Page.WELCOME;

            mainwindow.set_application (this);
            mainwindow.set_titlebar (header);
            mainwindow.window_position = Gtk.WindowPosition.CENTER;
            mainwindow.show_all ();
            if (!settings.show_window_decoration)
                mainwindow.decorated = false;

            /* mainwindow.size_allocate.connect (on_size_allocate); */
            mainwindow.key_press_event.connect (on_key_press_event);

            setup_drag_n_drop ();
        }

        private async void read_first_disk () {
            if (disk_manager.get_volumes ().length () <= 0)
                return;
            var volume = disk_manager.get_volumes ().nth_data (0);
            if (volume.can_mount () == true && volume.get_mount ().can_unmount () == false) {
                try {
                    yield volume.mount (MountMountFlags.NONE, null);
                } catch (Error e) {
                    critical (e.message);
                }
            }

            page = Page.PLAYER;
            var root = volume.get_mount ().get_default_location ();
            play_file (root.get_uri (), true);
        }

        public void on_configure_window (uint video_w, uint video_h) {
            Gdk.Rectangle monitor;
            var screen = Gdk.Screen.get_default ();
            screen.get_monitor_geometry (screen.get_monitor_at_window (mainwindow.get_window ()), out monitor);

            int width = 0, height = 0;
            if (monitor.width > video_w && monitor.height > video_h) {
                /* width = (int)video_w; */
                /* height = (int)video_h; */
                width = (int)(monitor.width * 0.9);
                height = (int)((double)video_h / video_w * width);
            } else {
                width = (int) mainwindow.get_allocated_width ();
                height = (int) mainwindow.get_allocated_height ();
            }
            mainwindow.resize(width, height);
        }
        public void set_content_size (double width, double height, double content_height){
            double width_offset = mainwindow.get_allocated_width () - width;
            double height_offset = mainwindow.get_allocated_height () - content_height;

            print ("Width: %f, Height: %f, Offset: %f )\n", width, height,content_height);

            var geom = Gdk.Geometry ();
            geom.min_aspect = geom.max_aspect = (width + width_offset) / (height + height_offset);

            var w = mainwindow.get_allocated_width ();
            var h = (int) (w * geom.max_aspect);
            int b, c;

            mainwindow.get_window ().set_geometry_hints (geom, Gdk.WindowHints.ASPECT);

            mainwindow.get_window ().constrain_size (geom, Gdk.WindowHints.ASPECT, w, h, out b, out c);
            print ("Result: %i %i == %i %i\n", w, h, b, c);
            mainwindow.get_window ().resize (b, c);

        }

        private void on_player_ended () {
            page = Page.WELCOME;
        }

        public bool on_key_press_event (Gdk.EventKey e) {
            switch (e.keyval) {
                case Gdk.Key.Escape:
                    App.get_instance ().mainwindow.destroy ();
                    break;
                case Gdk.Key.o:
                    App.get_instance ().run_open_file ();
                    break;
                case Gdk.Key.q:
                    App.get_instance ().mainwindow.destroy ();
                    break;
                default:
                    break;
            }
            return false;
        }

        public bool has_media_volumes () {
            return disk_manager.has_media_volumes ();
        }

        private inline void clear_video_settings () {
            settings.last_stopped = 0;
            settings.last_played_videos = null;
            settings.current_video = "";
        }

        public void run_open_file () {
            var file = new Gtk.FileChooserDialog (_("Open"), mainwindow, Gtk.FileChooserAction.OPEN,
                _("_Cancel"), Gtk.ResponseType.CANCEL, _("_Open"), Gtk.ResponseType.ACCEPT);
            file.select_multiple = true;

            var all_files_filter = new Gtk.FileFilter ();
            all_files_filter.set_filter_name (_("All files"));
            all_files_filter.add_pattern ("*");

            var video_filter = new Gtk.FileFilter ();
            video_filter.set_filter_name (_("Video files"));
            video_filter.add_mime_type ("video/*");

            file.add_filter (video_filter);
            file.add_filter (all_files_filter);

            file.set_current_folder (settings.last_folder);
            if (file.run () == Gtk.ResponseType.ACCEPT) {
                if (page == Page.WELCOME)
                    clear_video_settings ();

                File[] files = {};
                foreach (File item in file.get_files ()) {
                    files += item;
                }

                open (files, "");
                settings.last_folder = file.get_current_folder ();
            }

            file.destroy ();
        }

        public void run_open_dvd () {
            read_first_disk.begin ();
        }

        /*DnD*/
        private void setup_drag_n_drop () {
            Gtk.TargetEntry uris = {"text/uri-list", 0, 0};
            Gtk.drag_dest_set (mainwindow, Gtk.DestDefaults.ALL, {uris}, Gdk.DragAction.MOVE);
            mainwindow.drag_data_received.connect ( (ctx, x, y, sel, info, time) => {
                page = Page.PLAYER;
                File[] files = {};
                foreach (var uri in sel.get_uris ()) {
                    var file = File.new_for_uri (uri);
                    files += file;
                }
                open (files,"");
            });
        }

        public void resume_last_videos () {
            page = Page.PLAYER;

            var player = mainwindow.get_child () as PlayerPage;
            player.resume_last_videos ();
        }

        public void set_window_title (string title) {
            mainwindow.title = title;
        }

        /*
           make sure we are in player page and play file
        */
        internal void play_file (string uri, bool dont_modify = false) {
            if (page != Page.PLAYER)
                page = Page.PLAYER;

            PlayerPage player_page = mainwindow.get_child() as PlayerPage;
            player_page.play_file (uri);

        }

        public override void activate () {
            build ();
            if (settings.resume_videos == true
                && settings.last_played_videos.length > 0
                && settings.current_video != ""
                && file_exists (settings.current_video)) {

                /* if (settings.last_stopped > 0) { */
                /*     resume_last_videos (); */
                    /* open_file (settings.current_video); */
                    /* video_player.playing = false; */
                    /* Idle.add (() => {video_player.progress = settings.last_stopped; return false;}); */
                    /* video_player.playing = !settings.playback_wait; */
                /* } */
            }
        }

        //the application was requested to open some files
        public override void open (File[] files, string hint) {
            if (mainwindow == null)
                build ();

            if (page != Page.PLAYER)
                clear_video_settings ();

            page = Page.PLAYER;
            var player_page = (mainwindow.get_child () as PlayerPage);
            string[] videos = {};
            foreach (var file in files) {

                if (file.query_file_type (0) == FileType.DIRECTORY) {
                    Audience.recurse_over_dir (file, (file_ret) => {
                        player_page.append_to_playlist (file);
                        videos += file_ret.get_uri ();
                    });
                } else if (player_page.video_player.playing &&
                        PlayerPage.is_subtitle (file.get_uri ())) {
                    message ("is subtitle");
                    player_page.video_player.set_subtitle_uri (file.get_uri ());
                } else {
                    player_page.append_to_playlist (file);
                    videos += file.get_uri ();
                }
            }

            play_file (videos [0]);

            //TODO:enable notification
            /* if (video_player.uri != null) { // we already play some file */
            /*     if (files.length == 1) */
            /*         show_notification (_("Video added to playlist"), files[0].get_basename ()); */
            /*     else */
            /*         show_notification (_("%i videos added to playlist").printf (files.length), ""); */
            /* } else */
            /*     open_file(files[0].get_uri ()); */
        }

    }
}

public static void main (string [] args) {
    X.init_threads ();

    var err = GtkClutter.init (ref args);
    if (err != Clutter.InitError.SUCCESS) {
        error ("Could not initalize clutter! "+err.to_string ());
    }

    Gst.init (ref args);

    var app = Audience.App.get_instance ();

    app.run (args);
}
