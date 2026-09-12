#include "GTKBridge.h"
#include <gtk/gtk.h>

static OpusEvent callback;
static GtkApplication *app;
static GtkWidget *window, *sidebar, *rows, *heading, *entry, *error_label, *undo_button, *delete_list;
static GtkWidget *editor, *edit_title, *edit_day, *edit_course, *edit_kind, *edit_start, *edit_end, *edit_page, *page_fields;
static char *edit_id;
static GtkWidget *editor_error;

typedef struct { char *action, *id, *title, *day, *course; int kind, start, end, page; } Event;
static gboolean deliver(gpointer data) {
    Event *e = data;
    callback(e->action, e->id, e->title, e->day, e->course, e->kind, e->start, e->end, e->page);
    g_free(e->action); g_free(e->id); g_free(e->title); g_free(e->day); g_free(e->course); g_free(e);
    return G_SOURCE_REMOVE;
}
static void send(const char *action, const char *id, const char *title, const char *day, const char *course, int kind, int start, int end, int page) {
    Event *e = g_new0(Event, 1);
    e->action = g_strdup(action); e->id = g_strdup(id ? id : ""); e->title = g_strdup(title ? title : "");
    e->day = g_strdup(day ? day : ""); e->course = g_strdup(course ? course : "");
    e->kind = kind; e->start = start; e->end = end; e->page = page;
    // Defer rebuilding widgets until the GTK signal stack has unwound.
    g_idle_add(deliver, e);
}
static void clicked(GtkWidget *widget, gpointer unused) {
    send(g_object_get_data(G_OBJECT(widget), "action"), g_object_get_data(G_OBJECT(widget), "id"), "", "", "", 0, 0, 0, 0);
}
static GtkWidget *button(const char *label, const char *icon, const char *action, const char *id) {
    GtkWidget *b = icon ? gtk_button_new_from_icon_name(icon) : gtk_button_new_with_label(label);
    gtk_widget_set_tooltip_text(b, label);
    gtk_widget_set_size_request(b, 36, 36);
    gtk_widget_add_css_class(b, "flat");
    g_object_set_data_full(G_OBJECT(b), "action", g_strdup(action), g_free);
    g_object_set_data_full(G_OBJECT(b), "id", g_strdup(id), g_free);
    g_signal_connect(b, "clicked", G_CALLBACK(clicked), NULL);
    return b;
}
static void margins(GtkWidget *w, int amount) {
    gtk_widget_set_margin_start(w, amount); gtk_widget_set_margin_end(w, amount);
    gtk_widget_set_margin_top(w, amount); gtk_widget_set_margin_bottom(w, amount);
}
static void clear(GtkWidget *box) {
    GtkWidget *child;
    while ((child = gtk_widget_get_first_child(box))) gtk_box_remove(GTK_BOX(box), child);
}
static GtkWidget *label(const char *text) {
    GtkWidget *w = gtk_label_new(text);
    gtk_label_set_xalign(GTK_LABEL(w), 0);
    gtk_label_set_wrap(GTK_LABEL(w), TRUE);
    return w;
}
static void quick_add(GtkWidget *widget, gpointer unused) {
    send("add", "", gtk_editable_get_text(GTK_EDITABLE(entry)), "", "", 0, 0, 0, 0);
}
static void new_list(GtkWidget *widget, gpointer input) {
    send("new-list", "", gtk_editable_get_text(GTK_EDITABLE(input)), "", "", 0, 0, 0, 0);
}
static void activate(GtkApplication *application, gpointer unused) {
    if (window) { gtk_window_present(GTK_WINDOW(window)); return; }
    window = gtk_application_window_new(application);
    gtk_window_set_title(GTK_WINDOW(window), "Opus");
    gtk_window_set_default_size(GTK_WINDOW(window), 1000, 700);
    GtkWidget *header = gtk_header_bar_new();
    undo_button = button("Undo", "edit-undo-symbolic", "undo", "");
    gtk_header_bar_pack_start(GTK_HEADER_BAR(header), undo_button);
    gtk_header_bar_pack_end(GTK_HEADER_BAR(header), button("Quick Start", "help-browser-symbolic", "help", ""));
    gtk_header_bar_pack_end(GTK_HEADER_BAR(header), button("New task", "list-add-symbolic", "new", ""));
    gtk_window_set_titlebar(GTK_WINDOW(window), header);
    GtkWidget *layout = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    GtkWidget *rail = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8); margins(rail, 12);
    gtk_widget_set_size_request(rail, 180, -1);
    GtkWidget *nav_scroll = gtk_scrolled_window_new(); gtk_widget_set_vexpand(nav_scroll, TRUE);
    sidebar = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(nav_scroll), sidebar);
    gtk_box_append(GTK_BOX(rail), nav_scroll);
    GtkWidget *list_entry = gtk_entry_new(); gtk_entry_set_placeholder_text(GTK_ENTRY(list_entry), "New list…");
    g_signal_connect(list_entry, "activate", G_CALLBACK(new_list), list_entry);
    gtk_box_append(GTK_BOX(rail), list_entry);
    GtkWidget *content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12); margins(content, 20);
    gtk_widget_set_hexpand(content, TRUE);
    GtkWidget *title_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    heading = label(""); gtk_widget_add_css_class(heading, "title-1"); gtk_widget_set_hexpand(heading, TRUE);
    gtk_box_append(GTK_BOX(title_row), heading);
    delete_list = button("Remove list (tasks move to Inbox)", "user-trash-symbolic", "delete-list", "");
    gtk_box_append(GTK_BOX(title_row), delete_list); gtk_box_append(GTK_BOX(content), title_row);
    entry = gtk_entry_new(); g_signal_connect(entry, "activate", G_CALLBACK(quick_add), NULL);
    gtk_box_append(GTK_BOX(content), entry);
    error_label = label(""); gtk_widget_add_css_class(error_label, "error"); gtk_widget_set_visible(error_label, FALSE);
    gtk_box_append(GTK_BOX(content), error_label);
    GtkWidget *scroll = gtk_scrolled_window_new(); gtk_widget_set_vexpand(scroll, TRUE);
    rows = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), rows);
    gtk_box_append(GTK_BOX(content), scroll);
    gtk_box_append(GTK_BOX(layout), rail); gtk_box_append(GTK_BOX(layout), content);
    gtk_window_set_child(GTK_WINDOW(window), layout);
    gtk_window_present(GTK_WINDOW(window));
    send("ready", "", "", "", "", 0, 0, 0, 0);
}
int opus_run(OpusEvent event) {
    callback = event;
    app = gtk_application_new("io.github.streakwind.opus", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), 0, NULL);
    g_object_unref(app); return status;
}
void opus_begin(const char *title, const char *destination, int can_undo, int can_delete_list) {
    clear(sidebar); clear(rows);
    gtk_label_set_text(GTK_LABEL(heading), title);
    gtk_entry_set_placeholder_text(GTK_ENTRY(entry), destination);
    gtk_editable_set_text(GTK_EDITABLE(entry), "");
    gtk_widget_set_sensitive(undo_button, can_undo);
    gtk_widget_set_visible(delete_list, can_delete_list);
    opus_error("");
}
void opus_list(const char *id, const char *name, int selected) {
    GtkWidget *b = button(name, NULL, "select", id);
    if (selected) gtk_widget_add_css_class(b, "suggested-action");
    gtk_box_append(GTK_BOX(sidebar), b);
}
static void toggle(GtkCheckButton *check, gpointer unused) {
    send("toggle", g_object_get_data(G_OBJECT(check), "id"), "", "", "", 0, 0, 0, 0);
}
static void page_changed(GtkWidget *input, gpointer unused) {
    const char *text = gtk_editable_get_text(GTK_EDITABLE(input));
    send("page", g_object_get_data(G_OBJECT(input), "id"), text, "", "", 0, 0, 0, 0);
}
void opus_task(const char *id, const char *title, const char *detail, int done, int progress, int start, int end, int page) {
    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8); margins(row, 4);
    if (!progress) {
        GtkWidget *check = gtk_check_button_new(); gtk_check_button_set_active(GTK_CHECK_BUTTON(check), done);
        gtk_widget_set_tooltip_text(check, "Mark complete");
        g_object_set_data_full(G_OBJECT(check), "id", g_strdup(id), g_free);
        g_signal_connect(check, "toggled", G_CALLBACK(toggle), NULL); gtk_box_append(GTK_BOX(row), check);
    }
    GtkWidget *open = button("Edit task", NULL, "edit", id);
    GtkWidget *text = gtk_box_new(GTK_ORIENTATION_VERTICAL, 3);
    GtkWidget *name = label(title); if (done) gtk_widget_add_css_class(name, "dim-label");
    gtk_box_append(GTK_BOX(text), name);
    if (*detail) { GtkWidget *caption = label(detail); gtk_widget_add_css_class(caption, "dim-label"); gtk_box_append(GTK_BOX(text), caption); }
    gtk_button_set_child(GTK_BUTTON(open), text); gtk_widget_set_hexpand(open, TRUE);
    gtk_box_append(GTK_BOX(row), open);
    if (progress) {
        GtkWidget *input = gtk_entry_new(); char value[32]; g_snprintf(value, sizeof(value), "%d", page);
        gtk_editable_set_text(GTK_EDITABLE(input), value); gtk_editable_set_width_chars(GTK_EDITABLE(input), 5);
        gtk_widget_set_tooltip_text(input, "Last page read — press Enter to save");
        g_object_set_data_full(G_OBJECT(input), "id", g_strdup(id), g_free);
        g_signal_connect(input, "activate", G_CALLBACK(page_changed), NULL);
        gtk_box_append(GTK_BOX(row), input);
    }
    gtk_box_append(GTK_BOX(row), button("Delete task", "user-trash-symbolic", "delete", id));
    gtk_box_append(GTK_BOX(rows), row);
}
void opus_empty(const char *message) { GtkWidget *w = label(message); margins(w, 12); gtk_box_append(GTK_BOX(rows), w); }
void opus_error(const char *message) {
    if (editor && editor_error) {
        gtk_label_set_text(GTK_LABEL(editor_error), message);
        gtk_widget_set_visible(editor_error, *message != 0);
    }
    gtk_label_set_text(GTK_LABEL(error_label), message);
    gtk_widget_set_visible(error_label, *message != 0);
}
static GtkWidget *field(GtkWidget *box, const char *name, GtkWidget *input) {
    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
    GtkWidget *caption = label(name); gtk_widget_set_size_request(caption, 95, -1);
    gtk_widget_set_hexpand(input, TRUE);
    gtk_box_append(GTK_BOX(row), caption); gtk_box_append(GTK_BOX(row), input); gtk_box_append(GTK_BOX(box), row);
    return input;
}
static void editor_save(GtkWidget *widget, gpointer unused) {
    send("save", edit_id, gtk_editable_get_text(GTK_EDITABLE(edit_title)), gtk_editable_get_text(GTK_EDITABLE(edit_day)),
         gtk_combo_box_get_active_id(GTK_COMBO_BOX(edit_course)), gtk_check_button_get_active(GTK_CHECK_BUTTON(edit_kind)),
         gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(edit_start)), gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(edit_end)),
         gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(edit_page)));
}
static void editor_cancel(GtkWidget *widget, gpointer unused) { opus_editor_close(); }
static void kind_changed(GtkCheckButton *check, gpointer unused) { gtk_widget_set_visible(page_fields, gtk_check_button_get_active(check)); }
static void editor_destroy(GtkWidget *widget, gpointer unused) { editor = NULL; g_clear_pointer(&edit_id, g_free); }
void opus_editor(const char *id, const char *title, const char *day, const char *course, int kind, int start, int end, int page) {
    opus_editor_close(); edit_id = g_strdup(id);
    editor = gtk_window_new(); gtk_window_set_title(GTK_WINDOW(editor), *id ? "Edit task" : "New task");
    gtk_window_set_transient_for(GTK_WINDOW(editor), GTK_WINDOW(window)); gtk_window_set_modal(GTK_WINDOW(editor), TRUE);
    gtk_window_set_default_size(GTK_WINDOW(editor), 440, -1);
    g_signal_connect(editor, "destroy", G_CALLBACK(editor_destroy), NULL);
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12); margins(box, 24);
    edit_title = gtk_entry_new(); gtk_editable_set_text(GTK_EDITABLE(edit_title), title); gtk_entry_set_placeholder_text(GTK_ENTRY(edit_title), "Task title");
    gtk_box_append(GTK_BOX(box), edit_title);
    edit_course = field(box, "List", gtk_combo_box_text_new());
    edit_day = field(box, "Due", gtk_entry_new()); gtk_entry_set_placeholder_text(GTK_ENTRY(edit_day), "YYYY-MM-DD (optional)"); gtk_editable_set_text(GTK_EDITABLE(edit_day), day);
    edit_kind = gtk_check_button_new_with_label("Textbook notes"); gtk_check_button_set_active(GTK_CHECK_BUTTON(edit_kind), kind); gtk_box_append(GTK_BOX(box), edit_kind);
    page_fields = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    edit_start = field(page_fields, "First page", gtk_spin_button_new_with_range(1, 1000000, 1)); gtk_spin_button_set_value(GTK_SPIN_BUTTON(edit_start), start);
    edit_end = field(page_fields, "Last page", gtk_spin_button_new_with_range(1, 1000000, 1)); gtk_spin_button_set_value(GTK_SPIN_BUTTON(edit_end), end);
    edit_page = field(page_fields, "Read through", gtk_spin_button_new_with_range(0, 1000000, 1)); gtk_spin_button_set_value(GTK_SPIN_BUTTON(edit_page), page);
    gtk_widget_set_visible(page_fields, kind); g_signal_connect(edit_kind, "toggled", G_CALLBACK(kind_changed), NULL); gtk_box_append(GTK_BOX(box), page_fields);
    editor_error = label(""); gtk_widget_add_css_class(editor_error, "error"); gtk_widget_set_visible(editor_error, FALSE); gtk_box_append(GTK_BOX(box), editor_error);
    GtkWidget *actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8); gtk_widget_set_halign(actions, GTK_ALIGN_END);
    GtkWidget *cancel = gtk_button_new_with_label("Cancel"); g_signal_connect(cancel, "clicked", G_CALLBACK(editor_cancel), NULL);
    GtkWidget *save = gtk_button_new_with_label("Save"); gtk_widget_add_css_class(save, "suggested-action"); g_signal_connect(save, "clicked", G_CALLBACK(editor_save), NULL);
    gtk_box_append(GTK_BOX(actions), cancel); gtk_box_append(GTK_BOX(actions), save); gtk_box_append(GTK_BOX(box), actions);
    gtk_window_set_child(GTK_WINDOW(editor), box); gtk_window_present(GTK_WINDOW(editor)); gtk_widget_grab_focus(edit_title);
}
void opus_editor_list(const char *id, const char *name, int selected) {
    gtk_combo_box_text_append(GTK_COMBO_BOX_TEXT(edit_course), id, name);
    if (selected) gtk_combo_box_set_active_id(GTK_COMBO_BOX(edit_course), id);
}
void opus_editor_close(void) { if (editor) gtk_window_destroy(GTK_WINDOW(editor)); }
void opus_quit(void) { g_application_quit(G_APPLICATION(app)); }
