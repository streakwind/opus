#include "OpusWidgets.h"
#include <math.h>
#include <string.h>

static void button_clicked(GtkButton *button, gpointer unused) {
    (void)unused;
    OpusEventPayload event = {
        .action = g_object_get_data(G_OBJECT(button), "opus-action"),
        .id = g_object_get_data(G_OBJECT(button), "opus-id"),
        .payload = g_object_get_data(G_OBJECT(button), "opus-payload"),
        .kind = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "opus-kind"))
    };
    opus_send(&event);
}

GtkWidget *opus_label(const char *text) {
    GtkWidget *label = gtk_label_new(text ? text : "");
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
    gtk_label_set_wrap(GTK_LABEL(label), TRUE);
    return label;
}

GtkWidget *opus_button(const char *label, const char *icon, const char *action,
                       const char *id) {
    GtkWidget *button = icon
        ? gtk_button_new_from_icon_name(icon)
        : gtk_button_new_with_label(label ? label : "");
    gtk_widget_set_tooltip_text(button, label);
    if (label && *label) {
        opus_set_accessible_name(button, label);
    }
    gtk_widget_add_css_class(button, "flat");
    if (action) {
        g_object_set_data_full(G_OBJECT(button), "opus-action",
                               g_strdup(action), g_free);
        g_object_set_data_full(G_OBJECT(button), "opus-id",
                               g_strdup(id ? id : ""), g_free);
        g_signal_connect(button, "clicked", G_CALLBACK(button_clicked), NULL);
    }
    return button;
}

GtkWidget *opus_field(GtkWidget *box, const char *name, GtkWidget *input) {
    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    GtkWidget *caption = opus_label(name);
    gtk_widget_add_css_class(caption, "opus-field-label");
    gtk_widget_set_hexpand(input, TRUE);
    gtk_box_append(GTK_BOX(row), caption);
    gtk_box_append(GTK_BOX(row), input);
    gtk_box_append(GTK_BOX(box), row);
    return input;
}

void opus_margins(GtkWidget *widget, int amount) {
    gtk_widget_set_margin_start(widget, amount);
    gtk_widget_set_margin_end(widget, amount);
    gtk_widget_set_margin_top(widget, amount);
    gtk_widget_set_margin_bottom(widget, amount);
}

void opus_clear_box(GtkWidget *box) {
    if (!box || !GTK_IS_BOX(box)) {
        return;
    }
    GtkWidget *child;
    while ((child = gtk_widget_get_first_child(box)) != NULL) {
        gtk_box_remove(GTK_BOX(box), child);
    }
}

void opus_set_accessible_name(GtkWidget *widget, const char *name) {
    if (!widget || !name) {
        return;
    }
    gtk_accessible_update_property(GTK_ACCESSIBLE(widget),
                                   GTK_ACCESSIBLE_PROPERTY_LABEL, name, -1);
}

void opus_set_identity(GtkWidget *widget, const char *format, const char *id) {
    char *name = id ? g_strdup_printf(format, id) : g_strdup(format);
    gtk_widget_set_name(widget, name);
    opus_set_accessible_name(widget, name);
    g_free(name);
}

GtkWidget *opus_scrolled_box(GtkWidget **box_out) {
    GtkWidget *scroll = gtk_scrolled_window_new();
    gtk_widget_set_hexpand(scroll, TRUE);
    gtk_widget_set_vexpand(scroll, TRUE);
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), box);
    if (box_out) {
        *box_out = box;
    }
    return scroll;
}

GdkRGBA opus_color(const char *name) {
    struct NamedColor {
        const char *name;
        const char *hex;
    };
    static const struct NamedColor colors[] = {
        {"blue", "#3478c9"}, {"purple", "#7850c2"}, {"pink", "#c64c85"},
        {"orange", "#de6e29"}, {"red", "#c74047"}, {"brown", "#946345"},
        {"green", "#339461"}, {"teal", "#21919c"}, {"indigo", "#5957d6"},
        {"cyan", "#2ea3c2"}, {"mint", "#33b294"}, {"yellow", "#dbae24"}
    };
    const char *hex = "#3478c9";
    if (name && name[0] == '#' && strlen(name) == 7) {
        hex = name;
    } else {
        for (guint i = 0; i < G_N_ELEMENTS(colors); i++) {
            if (name && g_str_equal(name, colors[i].name)) {
                hex = colors[i].hex;
                break;
            }
        }
    }
    GdkRGBA color = {0};
    gdk_rgba_parse(&color, hex);
    return color;
}

static void draw_dot(GtkDrawingArea *area, cairo_t *cr, int width, int height,
                     gpointer data) {
    (void)area;
    GdkRGBA color = opus_color(data);
    gdk_cairo_set_source_rgba(cr, &color);
    double radius = MIN(width, height) / 2.0;
    cairo_arc(cr, width / 2.0, height / 2.0, radius, 0, 2 * G_PI);
    cairo_fill(cr);
}

GtkWidget *opus_color_dot(const char *color, int size) {
    GtkWidget *dot = gtk_drawing_area_new();
    gtk_widget_set_size_request(dot, size, size);
    gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(dot), draw_dot,
                                   g_strdup(color ? color : "blue"), g_free);
    return dot;
}

void opus_append_dropdown(GtkWidget *dropdown, GPtrArray *ids, const char *id,
                          const char *name, const char *selected_id, int selected) {
    if (!dropdown || !ids) {
        return;
    }
    g_ptr_array_add(ids, g_strdup(id ? id : ""));
    GtkStringList *model = GTK_STRING_LIST(
        gtk_drop_down_get_model(GTK_DROP_DOWN(dropdown)));
    gtk_string_list_append(model, name ? name : "");
    if (selected || (selected_id && g_strcmp0(selected_id, id) == 0)) {
        gtk_drop_down_set_selected(GTK_DROP_DOWN(dropdown), ids->len - 1);
    }
}

const char *opus_dropdown_id(GtkWidget *dropdown, GPtrArray *ids) {
    if (!dropdown || !ids || ids->len == 0) {
        return "";
    }
    guint selected = gtk_drop_down_get_selected(GTK_DROP_DOWN(dropdown));
    if (selected == GTK_INVALID_LIST_POSITION || selected >= ids->len) {
        return "";
    }
    return g_ptr_array_index(ids, selected);
}

char *opus_text_view_text(GtkWidget *view) {
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(view));
    GtkTextIter start;
    GtkTextIter end;
    gtk_text_buffer_get_bounds(buffer, &start, &end);
    return gtk_text_buffer_get_text(buffer, &start, &end, FALSE);
}

char *opus_json_escape(const char *text) {
    GString *escaped = g_string_new("");
    const unsigned char *cursor = (const unsigned char *)(text ? text : "");
    for (; *cursor; cursor++) {
        switch (*cursor) {
        case '"': g_string_append(escaped, "\\\""); break;
        case '\\': g_string_append(escaped, "\\\\"); break;
        case '\n': g_string_append(escaped, "\\n"); break;
        case '\r': g_string_append(escaped, "\\r"); break;
        case '\t': g_string_append(escaped, "\\t"); break;
        default:
            if (*cursor < 0x20) {
                g_string_append_printf(escaped, "\\u%04x", *cursor);
            } else {
                g_string_append_c(escaped, (char)*cursor);
            }
        }
    }
    return g_string_free(escaped, FALSE);
}

int opus_work_kind_int(const char *kind) {
    if (kind && g_strcmp0(kind, "progress") == 0) {
        return 1;
    }
    if (kind && g_strcmp0(kind, "assessment") == 0) {
        return 2;
    }
    return 0;
}

void opus_set_work_kind(GtkWidget *widget, const char *kind) {
    g_object_set_data(G_OBJECT(widget), "opus-kind",
                      GINT_TO_POINTER(opus_work_kind_int(kind)));
}

GtkWidget *opus_spin_int(int value, int min, int max) {
    GtkWidget *spin = gtk_spin_button_new_with_range(min, max, 1);
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(spin), value);
    return spin;
}

GtkWidget *opus_text_entry(const char *text) {
    GtkWidget *entry = gtk_entry_new();
    gtk_editable_set_text(GTK_EDITABLE(entry), text ? text : "");
    return entry;
}

GtkWidget *opus_notes_view(const char *text) {
    GtkWidget *scroll = gtk_scrolled_window_new();
    gtk_widget_set_size_request(scroll, -1, 120);
    GtkWidget *view = gtk_text_view_new();
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view), GTK_WRAP_WORD);
    if (text && *text) {
        gtk_text_buffer_set_text(gtk_text_view_get_buffer(GTK_TEXT_VIEW(view)),
                                 text, -1);
    }
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), view);
    return scroll;
}

GtkWidget *opus_kind_dropdown(int kind) {
    GtkWidget *dropdown = gtk_drop_down_new_from_strings(
        (const char *[]) {"Task", "Progress", "Assessment", NULL});
    kind = CLAMP(kind, 0, 2);
    gtk_drop_down_set_selected(GTK_DROP_DOWN(dropdown), (guint)kind);
    return dropdown;
}

static const char *color_names[] = {
    "blue", "purple", "pink", "orange", "red", "brown",
    "green", "teal", "indigo", "cyan", "mint", "yellow", NULL
};

GtkWidget *opus_color_dropdown(const char *selected) {
    static const char *labels[] = {
        "Blue", "Purple", "Pink", "Orange", "Red", "Brown",
        "Green", "Teal", "Indigo", "Cyan", "Mint", "Yellow", NULL
    };
    GtkStringList *model = gtk_string_list_new(labels);
    GtkWidget *dropdown = gtk_drop_down_new(G_LIST_MODEL(model), NULL);
    g_object_unref(model);
    int index = 0;
    for (guint i = 0; color_names[i]; i++) {
        if (selected && g_strcmp0(selected, color_names[i]) == 0) {
            index = (int)i;
            break;
        }
    }
    gtk_drop_down_set_selected(GTK_DROP_DOWN(dropdown), (guint)index);
    return dropdown;
}

const char *opus_color_dropdown_name(GtkWidget *dropdown) {
    guint selected = gtk_drop_down_get_selected(GTK_DROP_DOWN(dropdown));
    if (selected >= G_N_ELEMENTS(color_names) - 1) {
        return "blue";
    }
    return color_names[selected];
}

static void weekday_toggled(GtkCheckButton *check, gpointer data) {
    (void)check;
    (void)data;
}

GtkWidget *opus_weekday_box(int selected_mask) {
    static const char *labels[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    for (int day = 1; day <= 7; day++) {
        GtkWidget *toggle = gtk_check_button_new_with_label(labels[day - 1]);
        if (selected_mask & (1 << day)) {
            gtk_check_button_set_active(GTK_CHECK_BUTTON(toggle), TRUE);
        }
        g_object_set_data(G_OBJECT(toggle), "opus-day", GINT_TO_POINTER(day));
        g_signal_connect(toggle, "toggled", G_CALLBACK(weekday_toggled), NULL);
        gtk_box_append(GTK_BOX(box), toggle);
    }
    return box;
}

int opus_weekday_mask(GtkWidget *box) {
    int mask = 0;
    if (!box) {
        return mask;
    }
    GtkWidget *child = gtk_widget_get_first_child(box);
    while (child) {
        if (GTK_IS_CHECK_BUTTON(child) &&
            gtk_check_button_get_active(GTK_CHECK_BUTTON(child))) {
            int day = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(child), "opus-day"));
            mask |= (1 << day);
        }
        child = gtk_widget_get_next_sibling(child);
    }
    return mask;
}

static void clear_editor_state(void) {
    opus_ui.editor = NULL;
    opus_ui.editor_dim = NULL;
    opus_ui.editor_card = NULL;
    opus_ui.editor_heading = NULL;
    opus_ui.editor_error = NULL;
    opus_ui.editor_body = NULL;
    opus_ui.editor_type = 0;
    g_free(opus_ui.editor_id);
    opus_ui.editor_id = NULL;
    g_free(opus_ui.editor_rule_id);
    opus_ui.editor_rule_id = NULL;
    opus_ui.editor_exists = 0;
    opus_ui.editor_has_rule = 0;
    opus_ui.editor_title = NULL;
    opus_ui.editor_list = NULL;
    opus_ui.editor_day = NULL;
    opus_ui.editor_kind = NULL;
    opus_ui.editor_confirmed = NULL;
    opus_ui.editor_notes = NULL;
    opus_ui.editor_start = NULL;
    opus_ui.editor_target = NULL;
    opus_ui.editor_current = NULL;
    opus_ui.editor_progress_box = NULL;
    opus_ui.editor_name = NULL;
    opus_ui.editor_color = NULL;
    opus_ui.editor_times_box = NULL;
    opus_ui.editor_weekday_box = NULL;
    opus_ui.editor_interval = NULL;
    opus_ui.editor_start_date = NULL;
    opus_ui.editor_end_date = NULL;
    opus_ui.editor_enabled = NULL;
    opus_ui.editor_rule_schedule = NULL;
    opus_ui.editor_start_minute = NULL;
    opus_ui.editor_duration = NULL;
    opus_ui.editor_rule_progress_box = NULL;
    opus_ui.editor_schedule_box = NULL;
    opus_ui.editor_repeat_enabled = NULL;
    opus_ui.editor_repeat_end = NULL;
    opus_ui.editor_delete_scope = NULL;
    if (opus_ui.editor_course_ids) {
        g_ptr_array_unref(opus_ui.editor_course_ids);
        opus_ui.editor_course_ids = NULL;
    }
    if (opus_ui.editor_time_rows) {
        g_ptr_array_unref(opus_ui.editor_time_rows);
        opus_ui.editor_time_rows = NULL;
    }
    opus_ui.editor_save = NULL;
}

static void editor_destroyed(GtkWidget *widget, gpointer unused) {
    (void)unused;
    if (widget == opus_ui.editor || widget == opus_ui.editor_dim) {
        clear_editor_state();
    }
}

static void editor_cancel(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    opus_send_action("editor-cancel");
}

static gboolean editor_key_pressed(GtkEventControllerKey *controller,
                                   guint keyval, guint keycode,
                                   GdkModifierType state, gpointer unused) {
    (void)controller;
    (void)keycode;
    (void)unused;
    if (keyval == GDK_KEY_Escape) {
        opus_send_action("editor-cancel");
        return TRUE;
    }
    if ((state & GDK_CONTROL_MASK) &&
        (keyval == GDK_KEY_Return || keyval == GDK_KEY_KP_Enter) &&
        opus_ui.editor_save) {
        opus_ui.editor_save(NULL, NULL);
        return TRUE;
    }
    return FALSE;
}

void opus_editor_window_begin(const char *title, int type) {
    opus_editors_close(FALSE);
    opus_ui.editor_type = type;
    opus_ui.editor_save = NULL;

    opus_ui.editor_dim = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_add_css_class(opus_ui.editor_dim, "opus-overlay-dim");
    gtk_widget_set_hexpand(opus_ui.editor_dim, TRUE);
    gtk_widget_set_vexpand(opus_ui.editor_dim, TRUE);
    g_signal_connect(opus_ui.editor_dim, "destroy",
                     G_CALLBACK(editor_destroyed), NULL);

    GtkWidget *center = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_set_halign(center, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(center, GTK_ALIGN_CENTER);
    gtk_widget_set_hexpand(center, TRUE);
    gtk_widget_set_vexpand(center, TRUE);

    opus_ui.editor = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    opus_ui.editor_card = opus_ui.editor;
    gtk_widget_add_css_class(opus_ui.editor, "opus-editor-card");
    gtk_widget_set_size_request(opus_ui.editor, 460, 520);
    opus_set_accessible_name(opus_ui.editor, title ? title : "Editor");
    gtk_widget_set_name(opus_ui.editor, title ? title : "Editor");

    GtkEventController *keys = gtk_event_controller_key_new();
    g_signal_connect(keys, "key-pressed",
                     G_CALLBACK(editor_key_pressed), NULL);
    gtk_widget_add_controller(opus_ui.editor, keys);

    GtkWidget *header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    opus_margins(header, 16);
    opus_ui.editor_heading = opus_label(title ? title : "Editor");
    gtk_widget_add_css_class(opus_ui.editor_heading, "opus-editor-title");
    gtk_widget_set_hexpand(opus_ui.editor_heading, TRUE);
    gtk_box_append(GTK_BOX(header), opus_ui.editor_heading);
    GtkWidget *close = gtk_button_new_from_icon_name("window-close-symbolic");
    gtk_widget_add_css_class(close, "flat");
    gtk_widget_set_tooltip_text(close, "Close");
    g_signal_connect(close, "clicked", G_CALLBACK(editor_cancel), NULL);
    gtk_box_append(GTK_BOX(header), close);
    gtk_box_append(GTK_BOX(opus_ui.editor), header);
    gtk_box_append(GTK_BOX(opus_ui.editor),
                   gtk_separator_new(GTK_ORIENTATION_HORIZONTAL));

    GtkWidget *body_wrap = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    opus_margins(body_wrap, 16);
    opus_ui.editor_error = opus_label("");
    gtk_widget_add_css_class(opus_ui.editor_error, "opus-error");
    gtk_widget_add_css_class(opus_ui.editor_error, "error");
    gtk_widget_set_visible(opus_ui.editor_error, FALSE);
    gtk_box_append(GTK_BOX(body_wrap), opus_ui.editor_error);
    opus_ui.editor_body = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
    GtkWidget *scroll = gtk_scrolled_window_new();
    gtk_widget_set_vexpand(scroll, TRUE);
    gtk_widget_set_size_request(scroll, -1, 360);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),
                                   GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll),
                                  opus_ui.editor_body);
    gtk_box_append(GTK_BOX(body_wrap), scroll);
    gtk_box_append(GTK_BOX(opus_ui.editor), body_wrap);

    gtk_box_append(GTK_BOX(center), opus_ui.editor);
    gtk_box_append(GTK_BOX(opus_ui.editor_dim), center);

    if (opus_ui.overlay) {
        gtk_overlay_add_overlay(GTK_OVERLAY(opus_ui.overlay),
                                opus_ui.editor_dim);
        gtk_widget_set_visible(opus_ui.editor_dim, TRUE);
    }
}

void opus_editor_add_actions(GtkWidget *box, const char *save_action,
                             const char *delete_action) {
    GtkWidget *actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_set_halign(actions, GTK_ALIGN_END);
    gtk_widget_set_margin_top(actions, 8);
    if (delete_action) {
        GtkWidget *remove = gtk_button_new_with_label("Delete");
        gtk_widget_add_css_class(remove, "opus-destructive");
        g_object_set_data_full(G_OBJECT(remove), "opus-action",
                               g_strdup(delete_action), g_free);
        g_signal_connect(remove, "clicked", G_CALLBACK(button_clicked), NULL);
        gtk_box_append(GTK_BOX(actions), remove);
    }
    GtkWidget *cancel = gtk_button_new_with_label("Cancel");
    g_signal_connect(cancel, "clicked", G_CALLBACK(editor_cancel), NULL);
    opus_set_accessible_name(cancel, "editor-cancel");
    gtk_box_append(GTK_BOX(actions), cancel);
    GtkWidget *save = gtk_button_new_with_label("Save");
    gtk_widget_add_css_class(save, "suggested-action");
    g_object_set_data_full(G_OBJECT(save), "opus-action",
                           g_strdup(save_action), g_free);
    g_signal_connect(save, "clicked", G_CALLBACK(button_clicked), NULL);
    gtk_box_append(GTK_BOX(actions), save);
    gtk_box_append(GTK_BOX(box), actions);
}

void opus_editors_close(gboolean notify) {
    if (opus_ui.editor_dim) {
        GtkWidget *dim = opus_ui.editor_dim;
        g_signal_handlers_disconnect_by_func(dim,
                                             G_CALLBACK(editor_destroyed), NULL);
        GtkWidget *parent = gtk_widget_get_parent(dim);
        if (parent && GTK_IS_OVERLAY(parent)) {
            gtk_overlay_remove_overlay(GTK_OVERLAY(parent), dim);
        } else if (parent && GTK_IS_BOX(parent)) {
            gtk_box_remove(GTK_BOX(parent), dim);
        }
        clear_editor_state();
    } else if (opus_ui.editor && GTK_IS_WINDOW(opus_ui.editor)) {
        GtkWidget *editor = opus_ui.editor;
        g_signal_handlers_disconnect_by_func(editor,
                                             G_CALLBACK(editor_destroyed), NULL);
        gtk_window_destroy(GTK_WINDOW(editor));
        clear_editor_state();
    }
    if (notify) {
        opus_send_action("close-editor");
    }
}

void opus_editor_close(void) {
    opus_editors_close(FALSE);
}
