#include "OpusWidgets.h"
#include "OpusTheme.h"

OpusBridgeState opus_ui = {0};
static OpusEventFn event_callback;

typedef struct {
    OpusEventPayload value;
    char *action;
    char *id;
    char *text;
    char *day;
    char *course;
    char *payload;
} PendingEvent;

static gboolean deliver_event(gpointer data) {
    PendingEvent *pending = data;
    if (event_callback) {
        event_callback(&pending->value);
    }
    g_free(pending->action);
    g_free(pending->id);
    g_free(pending->text);
    g_free(pending->day);
    g_free(pending->course);
    g_free(pending->payload);
    g_free(pending);
    return G_SOURCE_REMOVE;
}

void opus_send(const OpusEventPayload *event) {
    PendingEvent *pending = g_new0(PendingEvent, 1);
    pending->action = g_strdup(event && event->action ? event->action : "");
    pending->id = g_strdup(event && event->id ? event->id : "");
    pending->text = g_strdup(event && event->text ? event->text : "");
    pending->day = g_strdup(event && event->day ? event->day : "");
    pending->course = g_strdup(event && event->course ? event->course : "");
    pending->payload = g_strdup(event && event->payload ? event->payload : "");
    pending->value = event ? *event : (OpusEventPayload){0};
    pending->value.action = pending->action;
    pending->value.id = pending->id;
    pending->value.text = pending->text;
    pending->value.day = pending->day;
    pending->value.course = pending->course;
    pending->value.payload = pending->payload;
    g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, deliver_event, pending, NULL);
}

void opus_send_action(const char *action) {
    OpusEventPayload event = {.action = action};
    opus_send(&event);
}

void opus_send_id(const char *action, const char *id) {
    OpusEventPayload event = {.action = action, .id = id};
    opus_send(&event);
}

static void search_changed(GtkEditable *editable, gpointer unused) {
    (void)unused;
    OpusEventPayload event = {
        .action = "search",
        .text = gtk_editable_get_text(editable)
    };
    opus_send(&event);
}

static void new_list(GtkEntry *entry, gpointer unused) {
    (void)unused;
    const char *text = gtk_editable_get_text(GTK_EDITABLE(entry));
    if (*text) {
        OpusEventPayload event = {.action = "new-list", .text = text};
        opus_send(&event);
        gtk_editable_set_text(GTK_EDITABLE(entry), "");
    }
}

static void new_list_blank(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    OpusEventPayload event = {.action = "new-list", .text = ""};
    opus_send(&event);
}

static void nav_clicked(GtkButton *button, gpointer unused) {
    (void)unused;
    OpusEventPayload event = {
        .action = g_object_get_data(G_OBJECT(button), "opus-action"),
        .id = g_object_get_data(G_OBJECT(button), "opus-id")
    };
    opus_send(&event);
}

static gboolean main_key(GtkEventControllerKey *controller, guint keyval,
                         guint keycode, GdkModifierType state, gpointer unused) {
    (void)controller;
    (void)keycode;
    (void)unused;
    if ((state & GDK_CONTROL_MASK) && keyval == GDK_KEY_n) {
        OpusEventPayload event = {.action = "new-work", .kind = -1};
        opus_send(&event);
        return TRUE;
    }
    if ((state & GDK_CONTROL_MASK) && keyval == GDK_KEY_q) {
        opus_quit();
        return TRUE;
    }
    if ((state & GDK_CONTROL_MASK) && (state & GDK_SHIFT_MASK) &&
        (keyval == GDK_KEY_z || keyval == GDK_KEY_Z)) {
        opus_send_action("undo");
        return TRUE;
    }
    if (keyval == GDK_KEY_F1) {
        opus_send_action("help");
        return TRUE;
    }
    if (keyval == GDK_KEY_Escape && opus_ui.editor) {
        opus_send_action("editor-cancel");
        return TRUE;
    }
    return FALSE;
}

static void add_view(GtkStack *stack, int index, const char *name) {
    opus_ui.views[index] = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_add_css_class(opus_ui.views[index], "opus-view");
    gtk_widget_set_hexpand(opus_ui.views[index], TRUE);
    gtk_widget_set_vexpand(opus_ui.views[index], TRUE);
    gtk_stack_add_named(stack, opus_ui.views[index], name);
}

static const char *nav_icon(const char *id) {
    if (!id) {
        return "folder-symbolic";
    }
    if (g_strcmp0(id, "today") == 0) {
        return "weather-clear-symbolic";
    }
    if (g_strcmp0(id, "all") == 0) {
        return "view-list-symbolic";
    }
    if (g_strcmp0(id, "inbox") == 0) {
        return "mail-mailbox-symbolic";
    }
    if (g_strcmp0(id, "archive") == 0) {
        return "folder-symbolic";
    }
    if (g_strcmp0(id, "calendar") == 0) {
        return "x-office-calendar-symbolic";
    }
    if (g_strcmp0(id, "schedule") == 0) {
        return "preferences-system-time-symbolic";
    }
    if (g_strcmp0(id, "rhythm") == 0) {
        return "media-playlist-repeat-symbolic";
    }
    return NULL;
}

static void activate(GtkApplication *application, gpointer unused) {
    (void)unused;
    if (opus_ui.window) {
        gtk_window_present(GTK_WINDOW(opus_ui.window));
        return;
    }

    opus_theme_load();
    opus_ui.application = application;
    opus_ui.window = gtk_application_window_new(application);
    gtk_widget_add_css_class(opus_ui.window, "opus-window");
    gtk_window_set_title(GTK_WINDOW(opus_ui.window), "Opus");
    gtk_window_set_default_size(GTK_WINDOW(opus_ui.window), 1100, 760);

    GtkEventController *keys = gtk_event_controller_key_new();
    g_signal_connect(keys, "key-pressed", G_CALLBACK(main_key), NULL);
    gtk_widget_add_controller(opus_ui.window, keys);

    GtkWidget *header = gtk_header_bar_new();
    gtk_header_bar_set_show_title_buttons(GTK_HEADER_BAR(header), TRUE);
    gtk_header_bar_set_title_widget(GTK_HEADER_BAR(header), gtk_label_new(""));
    opus_ui.undo_button = opus_button("Undo", "edit-undo-symbolic", "undo", NULL);
    gtk_header_bar_pack_start(GTK_HEADER_BAR(header), opus_ui.undo_button);
    GtkWidget *new_button = opus_button("Add", "list-add-symbolic",
                                        "new-work", NULL);
    g_object_set_data(G_OBJECT(new_button), "opus-kind", GINT_TO_POINTER(-1));
    gtk_header_bar_pack_end(GTK_HEADER_BAR(header), new_button);
    gtk_header_bar_pack_end(GTK_HEADER_BAR(header),
                            opus_button("Help", "help-browser-symbolic", "help", NULL));
    gtk_window_set_titlebar(GTK_WINDOW(opus_ui.window), header);

    opus_ui.overlay = gtk_overlay_new();
    GtkWidget *layout = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_add_css_class(layout, "opus-shell");

    GtkWidget *rail = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_set_size_request(rail, 215, -1);
    gtk_widget_add_css_class(rail, "opus-sidebar");
    gtk_widget_add_css_class(rail, "sidebar");

    GtkWidget *brand = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    gtk_widget_add_css_class(brand, "opus-brand");
    GtkWidget *mark = opus_label("▣");
    gtk_widget_add_css_class(mark, "opus-brand-mark");
    GtkWidget *brand_title = opus_label("Opus");
    gtk_widget_add_css_class(brand_title, "opus-brand-title");
    gtk_box_append(GTK_BOX(brand), mark);
    gtk_box_append(GTK_BOX(brand), brand_title);
    gtk_box_append(GTK_BOX(rail), brand);

    GtkWidget *nav_scroll = gtk_scrolled_window_new();
    gtk_widget_set_vexpand(nav_scroll, TRUE);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(nav_scroll),
                                   GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    opus_ui.sidebar = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_add_css_class(opus_ui.sidebar, "opus-nav");
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(nav_scroll), opus_ui.sidebar);
    gtk_box_append(GTK_BOX(rail), nav_scroll);

    GtkWidget *footer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_add_css_class(footer, "opus-sidebar-footer");
    GtkWidget *list_entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(list_entry), "New list");
    opus_set_identity(list_entry, "new-list-entry", NULL);
    gtk_widget_set_hexpand(list_entry, TRUE);
    g_signal_connect(list_entry, "activate", G_CALLBACK(new_list), NULL);
    GtkWidget *new_list_button = gtk_button_new_from_icon_name("list-add-symbolic");
    gtk_widget_add_css_class(new_list_button, "flat");
    gtk_widget_set_tooltip_text(new_list_button, "New list");
    opus_set_identity(new_list_button, "New list button", NULL);
    g_signal_connect(new_list_button, "clicked", G_CALLBACK(new_list_blank), NULL);
    GtkWidget *settings = opus_button("Settings", "emblem-system-symbolic",
                                      "settings", NULL);
    opus_set_identity(settings, "Settings", NULL);
    gtk_box_append(GTK_BOX(footer), list_entry);
    gtk_box_append(GTK_BOX(footer), new_list_button);
    gtk_box_append(GTK_BOX(footer), settings);
    gtk_box_append(GTK_BOX(rail), footer);

    GtkWidget *content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_add_css_class(content, "opus-content");
    gtk_widget_set_hexpand(content, TRUE);

    opus_ui.title_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_add_css_class(opus_ui.title_row, "opus-detail-header");
    opus_ui.heading = opus_label("");
    gtk_widget_add_css_class(opus_ui.heading, "opus-heading");
    gtk_widget_add_css_class(opus_ui.heading, "title-1");
    gtk_widget_set_hexpand(opus_ui.heading, TRUE);
    gtk_box_append(GTK_BOX(opus_ui.title_row), opus_ui.heading);
    opus_ui.edit_list = opus_button("Edit list", "document-edit-symbolic",
                                    "edit-list", NULL);
    opus_ui.delete_list = opus_button("Delete list", "user-trash-symbolic",
                                      "delete-list", NULL);
    opus_ui.delete_archive = opus_button("Delete All", "user-trash-symbolic",
                                         "archive-delete-all", NULL);
    gtk_box_append(GTK_BOX(opus_ui.title_row), opus_ui.edit_list);
    gtk_box_append(GTK_BOX(opus_ui.title_row), opus_ui.delete_list);
    gtk_box_append(GTK_BOX(opus_ui.title_row), opus_ui.delete_archive);
    gtk_box_append(GTK_BOX(content), opus_ui.title_row);

    GtkWidget *toolbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_add_css_class(toolbar, "opus-toolbar");
    opus_ui.search_entry = gtk_search_entry_new();
    gtk_search_entry_set_placeholder_text(GTK_SEARCH_ENTRY(opus_ui.search_entry),
                                          "Search");
    gtk_widget_add_css_class(opus_ui.search_entry, "opus-search");
    opus_set_identity(opus_ui.search_entry, "search-entry", NULL);
    gtk_widget_set_hexpand(opus_ui.search_entry, TRUE);
    g_signal_connect(opus_ui.search_entry, "search-changed",
                     G_CALLBACK(search_changed), NULL);
    gtk_box_append(GTK_BOX(toolbar), opus_ui.search_entry);
    gtk_box_append(GTK_BOX(content), toolbar);

    opus_ui.error_label = opus_label("");
    gtk_widget_add_css_class(opus_ui.error_label, "opus-error");
    gtk_widget_add_css_class(opus_ui.error_label, "error");
    gtk_widget_set_visible(opus_ui.error_label, FALSE);
    gtk_widget_set_margin_start(opus_ui.error_label, 18);
    gtk_widget_set_margin_end(opus_ui.error_label, 18);
    gtk_box_append(GTK_BOX(content), opus_ui.error_label);

    opus_ui.stack = gtk_stack_new();
    gtk_stack_set_transition_type(GTK_STACK(opus_ui.stack),
                                  GTK_STACK_TRANSITION_TYPE_CROSSFADE);
    gtk_widget_set_hexpand(opus_ui.stack, TRUE);
    gtk_widget_set_vexpand(opus_ui.stack, TRUE);
    add_view(GTK_STACK(opus_ui.stack), 0, "tasks");
    add_view(GTK_STACK(opus_ui.stack), 1, "calendar");
    add_view(GTK_STACK(opus_ui.stack), 2, "schedule");
    add_view(GTK_STACK(opus_ui.stack), 3, "rhythm");
    gtk_box_append(GTK_BOX(content), opus_ui.stack);

    gtk_box_append(GTK_BOX(layout), rail);
    gtk_box_append(GTK_BOX(layout), content);
    gtk_overlay_set_child(GTK_OVERLAY(opus_ui.overlay), layout);
    gtk_window_set_child(GTK_WINDOW(opus_ui.window), opus_ui.overlay);
    gtk_window_present(GTK_WINDOW(opus_ui.window));
    opus_send_action("ready");
}

int opus_run(OpusEventFn event) {
    event_callback = event;
    GtkApplication *application = gtk_application_new(
        "io.github.streakwind.opus", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(application, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(application), 0, NULL);
    opus_ui.application = NULL;
    g_object_unref(application);
    return status;
}

void opus_shell_begin(const char *title, const char *placeholder, int can_undo,
                      int can_delete_list, int show_title, int view,
                      int can_delete_archive) {
    if (!opus_ui.window) {
        return;
    }
    view = CLAMP(view, 0, 3);
    opus_ui.active_view = view;
    opus_clear_box(opus_ui.sidebar);
    opus_views_reset(view);
    gtk_label_set_text(GTK_LABEL(opus_ui.heading), title ? title : "");
    gtk_widget_set_visible(opus_ui.title_row,
                           show_title || can_delete_list || can_delete_archive);
    gtk_widget_set_sensitive(opus_ui.undo_button, can_undo);
    gtk_widget_set_visible(opus_ui.edit_list, can_delete_list);
    gtk_widget_set_visible(opus_ui.delete_list, can_delete_list);
    gtk_widget_set_visible(opus_ui.delete_archive, can_delete_archive);
    if (opus_ui.quick_entry && placeholder && *placeholder) {
        gtk_entry_set_placeholder_text(GTK_ENTRY(opus_ui.quick_entry),
                                       placeholder);
    }
    static const char *names[] = {"tasks", "calendar", "schedule", "rhythm"};
    gtk_stack_set_visible_child_name(GTK_STACK(opus_ui.stack), names[view]);
    opus_error("");
}

void opus_nav(const char *id, const char *name, int selected, const char *color,
              int separator_before) {
    if (separator_before) {
        if (id && g_str_has_prefix(id, "list:")) {
            GtkWidget *section = opus_label("YOUR LISTS");
            gtk_widget_add_css_class(section, "opus-nav-section");
            gtk_box_append(GTK_BOX(opus_ui.sidebar), section);
        } else {
            GtkWidget *separator = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
            gtk_widget_set_margin_top(separator, 8);
            gtk_widget_set_margin_bottom(separator, 8);
            gtk_widget_set_margin_start(separator, 8);
            gtk_widget_set_margin_end(separator, 8);
            gtk_box_append(GTK_BOX(opus_ui.sidebar), separator);
        }
    }

    GtkWidget *button = gtk_button_new();
    gtk_widget_add_css_class(button, "opus-nav-button");
    gtk_widget_add_css_class(button, "flat");
    GtkWidget *line = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    const char *icon = nav_icon(id);
    if (color && *color) {
        gtk_box_append(GTK_BOX(line), opus_color_dot(color, 8));
    } else if (icon) {
        GtkWidget *image = gtk_image_new_from_icon_name(icon);
        gtk_widget_set_opacity(image, 0.75);
        gtk_box_append(GTK_BOX(line), image);
    }
    GtkWidget *caption = opus_label(name);
    gtk_widget_set_hexpand(caption, TRUE);
    gtk_box_append(GTK_BOX(line), caption);
    gtk_button_set_child(GTK_BUTTON(button), line);
    g_object_set_data_full(G_OBJECT(button), "opus-action",
                           g_strdup("select"), g_free);
    g_object_set_data_full(G_OBJECT(button), "opus-id",
                           g_strdup(id ? id : ""), g_free);
    g_signal_connect(button, "clicked", G_CALLBACK(nav_clicked), NULL);
    opus_set_identity(button, "nav-%s", id);
    if (selected) {
        gtk_widget_add_css_class(button, "opus-selected");
    }
    gtk_box_append(GTK_BOX(opus_ui.sidebar), button);
}

void opus_error(const char *message) {
    const char *value = message ? message : "";
    if (opus_ui.editor && opus_ui.editor_error) {
        gtk_label_set_text(GTK_LABEL(opus_ui.editor_error), value);
        gtk_widget_set_visible(opus_ui.editor_error, *value != '\0');
    }
    if (opus_ui.error_label) {
        gtk_label_set_text(GTK_LABEL(opus_ui.error_label), value);
        gtk_widget_set_visible(opus_ui.error_label, *value != '\0');
    }
}

void opus_quit(void) {
    if (opus_ui.application) {
        g_application_quit(G_APPLICATION(opus_ui.application));
    }
}
