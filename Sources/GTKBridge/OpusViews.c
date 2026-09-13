#include "OpusWidgets.h"

#define OPUS_HOUR_HEIGHT 60
#define OPUS_DAY_HEIGHT (24 * OPUS_HOUR_HEIGHT)
#define OPUS_DAY_WIDTH 190

typedef struct {
    GtkWidget *items;
    GtkWidget *overflow;
    int count;
} CalendarDay;

typedef struct {
    GtkWidget *fixed;
    char *day;
    double press_y;
    gboolean pressed;
} ScheduleDay;

static void calendar_day_free(gpointer data) {
    g_free(data);
}

static void schedule_day_free(gpointer data) {
    ScheduleDay *day = data;
    if (day) {
        g_free(day->day);
        g_free(day);
    }
}

static void closure_data_free(gpointer data, GClosure *closure) {
    (void)closure;
    g_free(data);
}

static void quick_add(GtkEntry *entry, gpointer unused) {
    (void)unused;
    const char *text = gtk_editable_get_text(GTK_EDITABLE(entry));
    if (!*text) {
        return;
    }
    OpusEventPayload event = {.action = "add", .text = text};
    opus_send(&event);
    gtk_editable_set_text(GTK_EDITABLE(entry), "");
}

void opus_views_reset(int view) {
    if (opus_ui.calendar_days) {
        g_hash_table_destroy(opus_ui.calendar_days);
        opus_ui.calendar_days = NULL;
    }
    if (opus_ui.schedule_days) {
        g_hash_table_destroy(opus_ui.schedule_days);
        opus_ui.schedule_days = NULL;
    }
    opus_ui.calendar_grid = NULL;
    opus_ui.calendar_undated = NULL;
    opus_ui.schedule_columns = NULL;
    opus_ui.rows = NULL;
    opus_ui.quick_entry = NULL;

    opus_clear_box(opus_ui.views[view]);
    if (view == 0 || view == 3 || view == 4) {
        if (view != 4) {
            GtkWidget *quick = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
            gtk_widget_add_css_class(quick, "opus-quick-entry");
            opus_ui.quick_entry = gtk_entry_new();
            gtk_entry_set_placeholder_text(GTK_ENTRY(opus_ui.quick_entry),
                                           view == 3 ? "Add a rhythm…" : "Add a task…");
            opus_set_identity(opus_ui.quick_entry,
                              view == 3 ? "add-rhythm" : "quick-entry", NULL);
            g_signal_connect(opus_ui.quick_entry, "activate", G_CALLBACK(quick_add), NULL);
            gtk_box_append(GTK_BOX(quick), opus_ui.quick_entry);
            gtk_box_append(GTK_BOX(opus_ui.views[view]), quick);
        }
        gtk_box_append(GTK_BOX(opus_ui.views[view]),
                       opus_scrolled_box(&opus_ui.rows));
    }
}

void opus_section(const char *title) {
    if (!opus_ui.rows) {
        return;
    }
    GtkWidget *label = opus_label(title);
    gtk_widget_add_css_class(label, "opus-section-label");
    gtk_widget_add_css_class(label, "heading");
    gtk_box_append(GTK_BOX(opus_ui.rows), label);
}

static void task_toggle(GtkButton *button, gpointer unused) {
    (void)unused;
    opus_send_id("toggle", g_object_get_data(G_OBJECT(button), "opus-id"));
}

static void page_changed(GtkEntry *entry, gpointer unused) {
    (void)unused;
    OpusEventPayload event = {
        .action = "page",
        .id = g_object_get_data(G_OBJECT(entry), "opus-id"),
        .text = gtk_editable_get_text(GTK_EDITABLE(entry))
    };
    opus_send(&event);
}

static void edit_work(GtkButton *button, gpointer unused) {
    (void)unused;
    OpusEventPayload event = {
        .action = "edit-work",
        .id = g_object_get_data(G_OBJECT(button), "opus-id"),
        .kind = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "opus-kind"))
    };
    opus_send(&event);
}

static void delete_work(GtkButton *button, gpointer unused) {
    (void)unused;
    OpusEventPayload event = {
        .action = "delete-work",
        .id = g_object_get_data(G_OBJECT(button), "opus-id"),
        .kind = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "opus-kind"))
    };
    opus_send(&event);
}

void opus_work_row(const char *id, const char *kind, const char *title,
                   const char *detail, int done, int progress, int start,
                   int end, int page, int confirmed, const char *color) {
    (void)start;
    (void)end;
    (void)confirmed;
    if (!opus_ui.rows) {
        return;
    }
    const gboolean assessment = g_strcmp0(kind, "assessment") == 0;
    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    gtk_widget_add_css_class(row, "opus-work-row");
    if (done) {
        gtk_widget_add_css_class(row, "opus-done");
    }
    opus_set_identity(row, "task-row-%s", id);

    if (!progress && !assessment) {
        GtkWidget *check = gtk_button_new_with_label(done ? "●" : "○");
        gtk_widget_add_css_class(check, "flat");
        gtk_widget_add_css_class(check, "opus-complete");
        g_object_set_data_full(G_OBJECT(check), "opus-id", g_strdup(id), g_free);
        opus_set_identity(check, "toggle-%s", id);
        gtk_widget_set_tooltip_text(check, done ? "Mark incomplete" : "Mark complete");
        g_signal_connect(check, "clicked", G_CALLBACK(task_toggle), NULL);
        gtk_box_append(GTK_BOX(row), check);
    } else if (assessment) {
        GtkWidget *mark = gtk_image_new_from_icon_name("x-office-calendar-symbolic");
        gtk_widget_set_opacity(mark, 0.8);
        gtk_box_append(GTK_BOX(row), mark);
    } else {
        gtk_box_append(GTK_BOX(row), opus_color_dot(color, 10));
    }

    GtkWidget *text = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    GtkWidget *name = opus_label(title);
    gtk_widget_add_css_class(name, "opus-work-title");
    if (done) {
        gtk_widget_add_css_class(name, "dim-label");
    }
    gtk_box_append(GTK_BOX(text), name);
    if (detail && *detail) {
        GtkWidget *meta = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
        if (!progress && color && *color) {
            gtk_box_append(GTK_BOX(meta), opus_color_dot(color, 5));
        }
        GtkWidget *caption = opus_label(detail);
        gtk_widget_add_css_class(caption, "opus-work-meta");
        gtk_widget_add_css_class(caption, "dim-label");
        gtk_box_append(GTK_BOX(meta), caption);
        gtk_box_append(GTK_BOX(text), meta);
    }
    gtk_widget_set_hexpand(text, TRUE);
    gtk_box_append(GTK_BOX(row), text);

    if (progress) {
        GtkWidget *input = gtk_entry_new();
        char value[32];
        g_snprintf(value, sizeof(value), "%d", page);
        gtk_editable_set_text(GTK_EDITABLE(input), value);
        gtk_editable_set_width_chars(GTK_EDITABLE(input), 5);
        gtk_entry_set_input_purpose(GTK_ENTRY(input), GTK_INPUT_PURPOSE_NUMBER);
        gtk_widget_set_tooltip_text(input, "Through — press Enter to save");
        g_object_set_data_full(G_OBJECT(input), "opus-id", g_strdup(id), g_free);
        opus_set_identity(input, "page-%s", id);
        g_signal_connect(input, "activate", G_CALLBACK(page_changed), NULL);
        gtk_box_append(GTK_BOX(row), input);
    }

    if (assessment) {
        GtkWidget *prepare = opus_button("Prepare", NULL, "prepare-task", id);
        opus_set_identity(prepare, "prepare-%s", id);
        gtk_box_append(GTK_BOX(row), prepare);
    }

    GtkWidget *edit = gtk_button_new_from_icon_name("document-edit-symbolic");
    gtk_widget_add_css_class(edit, "flat");
    gtk_widget_set_tooltip_text(edit, "Edit");
    g_object_set_data_full(G_OBJECT(edit), "opus-id", g_strdup(id), g_free);
    opus_set_work_kind(edit, kind);
    opus_set_identity(edit, "edit-work-%s", id);
    g_signal_connect(edit, "clicked", G_CALLBACK(edit_work), NULL);
    gtk_box_append(GTK_BOX(row), edit);

    GtkWidget *remove = gtk_button_new_from_icon_name("user-trash-symbolic");
    gtk_widget_add_css_class(remove, "flat");
    gtk_widget_set_tooltip_text(remove, "Delete");
    g_object_set_data_full(G_OBJECT(remove), "opus-id", g_strdup(id), g_free);
    opus_set_work_kind(remove, kind);
    opus_set_identity(remove, "delete-work-%s", id);
    g_signal_connect(remove, "clicked", G_CALLBACK(delete_work), NULL);
    gtk_box_append(GTK_BOX(row), remove);
    gtk_box_append(GTK_BOX(opus_ui.rows), row);
}

static void notes_changed(GtkTextBuffer *buffer, gpointer unused) {
    (void)unused;
    GtkTextIter start, end;
    gtk_text_buffer_get_bounds(buffer, &start, &end);
    char *text = gtk_text_buffer_get_text(buffer, &start, &end, FALSE);
    OpusEventPayload event = {
        .action = "save-notes",
        .id = g_object_get_data(G_OBJECT(buffer), "opus-id"),
        .course = g_object_get_data(G_OBJECT(buffer), "opus-course"),
        .text = text ? text : ""
    };
    opus_send(&event);
    g_free(text);
}

static void note_title_changed(GtkEditable *editable, gpointer unused) {
    (void)unused;
    OpusEventPayload event = {
        .action = "save-note-title",
        .id = g_object_get_data(G_OBJECT(editable), "opus-id"),
        .course = g_object_get_data(G_OBJECT(editable), "opus-course"),
        .text = gtk_editable_get_text(editable)
    };
    opus_send(&event);
}

static void add_note_clicked(GtkButton *button, gpointer unused) {
    (void)unused;
    OpusEventPayload event = {
        .action = "add-note",
        .id = g_object_get_data(G_OBJECT(button), "opus-id")
    };
    opus_send(&event);
}

static void delete_note_clicked(GtkButton *button, gpointer unused) {
    (void)unused;
    OpusEventPayload event = {
        .action = "delete-note",
        .id = g_object_get_data(G_OBJECT(button), "opus-id"),
        .course = g_object_get_data(G_OBJECT(button), "opus-course")
    };
    opus_send(&event);
}

void opus_list_note(const char *course_id, const char *note_id, const char *title, const char *markdown) {
    if (!opus_ui.rows) {
        return;
    }
    GtkWidget *header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *name = gtk_entry_new();
    gtk_editable_set_text(GTK_EDITABLE(name), title ? title : "");
    gtk_entry_set_placeholder_text(GTK_ENTRY(name), "Untitled note");
    gtk_widget_set_hexpand(name, TRUE);
    g_object_set_data_full(G_OBJECT(name), "opus-id", g_strdup(note_id ? note_id : ""), g_free);
    g_object_set_data_full(G_OBJECT(name), "opus-course", g_strdup(course_id ? course_id : ""), g_free);
    g_signal_connect(name, "changed", G_CALLBACK(note_title_changed), NULL);
    GtkWidget *remove = gtk_button_new_from_icon_name("user-trash-symbolic");
    gtk_widget_add_css_class(remove, "flat");
    gtk_widget_set_tooltip_text(remove, "Delete");
    g_object_set_data_full(G_OBJECT(remove), "opus-id", g_strdup(note_id ? note_id : ""), g_free);
    g_object_set_data_full(G_OBJECT(remove), "opus-course", g_strdup(course_id ? course_id : ""), g_free);
    g_signal_connect(remove, "clicked", G_CALLBACK(delete_note_clicked), NULL);
    gtk_box_append(GTK_BOX(header), name);
    gtk_box_append(GTK_BOX(header), remove);
    gtk_box_append(GTK_BOX(opus_ui.rows), header);
    GtkWidget *scroll = gtk_scrolled_window_new();
    gtk_widget_set_size_request(scroll, -1, 140);
    gtk_widget_set_hexpand(scroll, TRUE);
    GtkWidget *view = gtk_text_view_new();
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view), GTK_WRAP_WORD_CHAR);
    gtk_text_view_set_left_margin(GTK_TEXT_VIEW(view), 8);
    gtk_text_view_set_right_margin(GTK_TEXT_VIEW(view), 8);
    gtk_text_view_set_top_margin(GTK_TEXT_VIEW(view), 8);
    gtk_text_view_set_bottom_margin(GTK_TEXT_VIEW(view), 8);
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(view));
    if (markdown && *markdown) {
        gtk_text_buffer_set_text(buffer, markdown, -1);
    }
    g_object_set_data_full(G_OBJECT(buffer), "opus-id", g_strdup(note_id ? note_id : ""), g_free);
    g_object_set_data_full(G_OBJECT(buffer), "opus-course", g_strdup(course_id ? course_id : ""), g_free);
    g_signal_connect(buffer, "changed", G_CALLBACK(notes_changed), NULL);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), view);
    gtk_box_append(GTK_BOX(opus_ui.rows), scroll);
}

void opus_add_note(const char *course_id) {
    if (!opus_ui.rows) {
        return;
    }
    GtkWidget *add = gtk_button_new_with_label("Add a note");
    gtk_widget_add_css_class(add, "flat");
    g_object_set_data_full(G_OBJECT(add), "opus-id", g_strdup(course_id ? course_id : ""), g_free);
    g_signal_connect(add, "clicked", G_CALLBACK(add_note_clicked), NULL);
    gtk_box_append(GTK_BOX(opus_ui.rows), add);
}

void opus_empty(const char *message) {
    GtkWidget *parent = opus_ui.rows ? opus_ui.rows : opus_ui.views[opus_ui.active_view];
    GtkWidget *label = opus_label(message);
    gtk_widget_add_css_class(label, "opus-empty");
    gtk_widget_add_css_class(label, "dim-label");
    gtk_box_append(GTK_BOX(parent), label);
}

static void period_toggled(GtkToggleButton *button, gpointer unused) {
    (void)unused;
    if (!gtk_toggle_button_get_active(button)) {
        return;
    }
    OpusEventPayload event = {
        .action = g_object_get_data(G_OBJECT(button), "opus-action"),
        .value = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "opus-value"))
    };
    opus_send(&event);
}

static GtkWidget *period_controls(const char *action, int period,
                                  gboolean include_month) {
    static const char *labels[] = {"Day", "Week", "Month"};
    static const char *slugs[] = {"day", "week", "month"};
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_add_css_class(box, "opus-period");
    GtkWidget *first = NULL;
    int count = include_month ? 3 : 2;
    for (int i = 0; i < count; i++) {
        GtkWidget *toggle = gtk_toggle_button_new_with_label(labels[i]);
        if (first) {
            gtk_toggle_button_set_group(GTK_TOGGLE_BUTTON(toggle),
                                        GTK_TOGGLE_BUTTON(first));
        } else {
            first = toggle;
        }
        g_object_set_data_full(G_OBJECT(toggle), "opus-action",
                               g_strdup(action), g_free);
        g_object_set_data(G_OBJECT(toggle), "opus-value", GINT_TO_POINTER(i));
        gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(toggle), i == period);
        char *name = g_strdup_printf("%s-%s", action, slugs[i]);
        opus_set_accessible_name(toggle, name);
        gtk_widget_set_name(toggle, name);
        g_free(name);
        g_signal_connect(toggle, "toggled", G_CALLBACK(period_toggled), NULL);
        gtk_box_append(GTK_BOX(box), toggle);
    }
    return box;
}

static void navigate(GtkButton *button, gpointer unused) {
    (void)unused;
    OpusEventPayload event = {
        .action = g_object_get_data(G_OBJECT(button), "opus-action"),
        .value = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "opus-value"))
    };
    opus_send(&event);
}

static GtkWidget *nav_button(const char *label, const char *icon,
                             const char *action, int value) {
    GtkWidget *button = icon
        ? gtk_button_new_from_icon_name(icon)
        : gtk_button_new_with_label(label);
    gtk_widget_set_tooltip_text(button, label);
    g_object_set_data_full(G_OBJECT(button), "opus-action",
                           g_strdup(action), g_free);
    g_object_set_data(G_OBJECT(button), "opus-value", GINT_TO_POINTER(value));
    g_signal_connect(button, "clicked", G_CALLBACK(navigate), NULL);
    return button;
}

static GtkWidget *view_toolbar(const char *period_action,
                               const char *navigate_action, int period,
                               gboolean include_month) {
    GtkWidget *toolbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_box_append(GTK_BOX(toolbar),
                   period_controls(period_action, period, include_month));
    GtkWidget *spacer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_set_hexpand(spacer, TRUE);
    gtk_box_append(GTK_BOX(toolbar), spacer);
    gtk_box_append(GTK_BOX(toolbar),
                   nav_button("Previous", "go-previous-symbolic",
                              navigate_action, -1));
    gtk_box_append(GTK_BOX(toolbar),
                   nav_button("Today", NULL, navigate_action, 0));
    gtk_box_append(GTK_BOX(toolbar),
                   nav_button("Next", "go-next-symbolic",
                              navigate_action, 1));
    return toolbar;
}

static void calendar_day_clicked(GtkButton *button, gpointer unused) {
    (void)unused;
    OpusEventPayload event = {
        .action = "calendar-select-day",
        .day = g_object_get_data(G_OBJECT(button), "opus-day")
    };
    opus_send(&event);
}

static gboolean calendar_drop(GtkDropTarget *target, const GValue *value,
                              double x, double y, gpointer data) {
    (void)target;
    (void)x;
    (void)y;
    const char *payload = g_value_get_string(value);
    OpusEventPayload event = {
        .action = "calendar-drop",
        .day = data,
        .payload = payload
    };
    opus_send(&event);
    return TRUE;
}

void opus_calendar_begin(const char *heading, int period, int columns) {
    if (heading) {
        gtk_label_set_text(GTK_LABEL(opus_ui.heading), heading);
    }
    GtkWidget *view = opus_ui.views[1];
    gtk_box_append(GTK_BOX(view),
                   view_toolbar("calendar-period", "calendar-nav",
                                CLAMP(period, 0, 2), TRUE));
    GtkWidget *split = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_set_hexpand(split, TRUE);
    gtk_widget_set_vexpand(split, TRUE);

    GtkWidget *scroll = gtk_scrolled_window_new();
    gtk_widget_set_hexpand(scroll, TRUE);
    gtk_widget_set_vexpand(scroll, TRUE);
    opus_ui.calendar_grid = gtk_grid_new();
    gtk_grid_set_row_spacing(GTK_GRID(opus_ui.calendar_grid), 6);
    gtk_grid_set_column_spacing(GTK_GRID(opus_ui.calendar_grid), 6);
    gtk_grid_set_column_homogeneous(GTK_GRID(opus_ui.calendar_grid), TRUE);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll),
                                  opus_ui.calendar_grid);
    gtk_box_append(GTK_BOX(split), scroll);
    opus_ui.calendar_undated = NULL;

    gtk_box_append(GTK_BOX(view), split);
    opus_ui.calendar_columns = MAX(1, columns);
    opus_ui.calendar_index = 0;
    opus_ui.calendar_days = g_hash_table_new_full(g_str_hash, g_str_equal,
                                                  g_free, calendar_day_free);
}

void opus_calendar_day(const char *day, const char *label, int in_month,
                       int is_today, int selected) {
    if (!opus_ui.calendar_grid || !opus_ui.calendar_days) {
        return;
    }
    GtkWidget *cell = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    opus_margins(cell, 6);
    gtk_widget_set_size_request(cell, 120, 112);
    gtk_widget_add_css_class(cell, "opus-calendar-cell");
    gtk_widget_add_css_class(cell, "card");
    if (!in_month) {
        gtk_widget_add_css_class(cell, "opus-out-month");
    }
    if (is_today) {
        gtk_widget_add_css_class(cell, "opus-today");
    }
    if (selected) {
        gtk_widget_add_css_class(cell, "opus-selected");
        gtk_widget_add_css_class(cell, "accent");
    }
    GtkWidget *day_button = gtk_button_new_with_label(label ? label : "");
    gtk_widget_add_css_class(day_button, "flat");
    gtk_widget_add_css_class(day_button, "opus-calendar-day-number");
    g_object_set_data_full(G_OBJECT(day_button), "opus-day",
                           g_strdup(day ? day : ""), g_free);
    g_signal_connect(day_button, "clicked", G_CALLBACK(calendar_day_clicked), NULL);
    gtk_box_append(GTK_BOX(cell), day_button);

    CalendarDay *info = g_new0(CalendarDay, 1);
    info->items = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_box_append(GTK_BOX(cell), info->items);
    info->overflow = opus_label("");
    gtk_widget_add_css_class(info->overflow, "dim-label");
    gtk_widget_set_visible(info->overflow, FALSE);
    gtk_box_append(GTK_BOX(cell), info->overflow);

    GtkDropTarget *drop = gtk_drop_target_new(G_TYPE_STRING, GDK_ACTION_MOVE);
    g_signal_connect_data(drop, "drop", G_CALLBACK(calendar_drop),
                          g_strdup(day ? day : ""), closure_data_free, 0);
    gtk_widget_add_controller(cell, GTK_EVENT_CONTROLLER(drop));

    int column = opus_ui.calendar_index % opus_ui.calendar_columns;
    int row = opus_ui.calendar_index / opus_ui.calendar_columns;
    gtk_grid_attach(GTK_GRID(opus_ui.calendar_grid), cell, column, row, 1, 1);
    g_hash_table_insert(opus_ui.calendar_days, g_strdup(day ? day : ""), info);
    opus_ui.calendar_index++;
}

static char *calendar_drag_payload(const char *kind, const char *id) {
    const char *prefix = "task";
    if (kind && g_strcmp0(kind, "assessment") == 0) {
        prefix = "assessment";
    }
    return g_strdup_printf("%s:%s", prefix, id ? id : "");
}

static GdkContentProvider *calendar_drag(GtkDragSource *source, double x,
                                         double y, gpointer data) {
    (void)source;
    (void)x;
    (void)y;
    return gdk_content_provider_new_typed(G_TYPE_STRING, data);
}

static void calendar_item_clicked(GtkButton *button, gpointer unused) {
    (void)unused;
    OpusEventPayload event = {
        .action = "edit-work",
        .id = g_object_get_data(G_OBJECT(button), "opus-id"),
        .kind = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "opus-kind"))
    };
    opus_send(&event);
}

void opus_calendar_item(const char *day, const char *id, const char *kind,
                        const char *title, int done, int confirmed,
                        const char *color) {
    (void)done;
    (void)confirmed;
    CalendarDay *info = opus_ui.calendar_days
        ? g_hash_table_lookup(opus_ui.calendar_days, day)
        : NULL;
    if (!info) {
        return;
    }
    info->count++;
    if (info->count > 4) {
        char overflow[32];
        g_snprintf(overflow, sizeof(overflow), "+%d more", info->count - 4);
        gtk_label_set_text(GTK_LABEL(info->overflow), overflow);
        gtk_widget_set_visible(info->overflow, TRUE);
        return;
    }

    GtkWidget *button = gtk_button_new();
    gtk_widget_add_css_class(button, "flat");
    gtk_widget_add_css_class(button, "opus-calendar-item");
    GtkWidget *line = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5);
    gtk_box_append(GTK_BOX(line), opus_color_dot(color, 8));
    GtkWidget *caption = opus_label(title);
    gtk_label_set_ellipsize(GTK_LABEL(caption), PANGO_ELLIPSIZE_END);
    gtk_widget_set_hexpand(caption, TRUE);
    gtk_box_append(GTK_BOX(line), caption);
    gtk_button_set_child(GTK_BUTTON(button), line);
    g_object_set_data_full(G_OBJECT(button), "opus-id", g_strdup(id), g_free);
    opus_set_work_kind(button, kind);
    g_signal_connect(button, "clicked", G_CALLBACK(calendar_item_clicked), NULL);

    char *payload = calendar_drag_payload(kind, id);
    GtkDragSource *source = gtk_drag_source_new();
    gtk_drag_source_set_actions(source, GDK_ACTION_MOVE);
    g_signal_connect_data(source, "prepare", G_CALLBACK(calendar_drag), payload,
                          closure_data_free, 0);
    gtk_widget_add_controller(button, GTK_EVENT_CONTROLLER(source));
    gtk_box_append(GTK_BOX(info->items), button);
}

void opus_calendar_undated(const char *id, const char *kind, const char *title,
                           const char *detail, const char *color) {
    (void)id;
    (void)kind;
    (void)title;
    (void)detail;
    (void)color;
    if (!opus_ui.calendar_undated) {
        return;
    }
    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_add_css_class(row, "opus-work-row");
    opus_set_identity(row, "undated-%s", id);
    gtk_box_append(GTK_BOX(row), opus_color_dot(color, 8));
    GtkWidget *text = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_set_hexpand(text, TRUE);
    GtkWidget *name = opus_label(title);
    gtk_widget_add_css_class(name, "opus-work-title");
    gtk_box_append(GTK_BOX(text), name);
    if (detail && *detail) {
        GtkWidget *caption = opus_label(detail);
        gtk_widget_add_css_class(caption, "opus-work-meta");
        gtk_widget_add_css_class(caption, "dim-label");
        gtk_box_append(GTK_BOX(text), caption);
    }
    gtk_box_append(GTK_BOX(row), text);
    GtkWidget *edit = gtk_button_new_from_icon_name("document-edit-symbolic");
    gtk_widget_add_css_class(edit, "flat");
    g_object_set_data_full(G_OBJECT(edit), "opus-id", g_strdup(id), g_free);
    opus_set_work_kind(edit, kind);
    g_signal_connect(edit, "clicked", G_CALLBACK(edit_work), NULL);
    gtk_box_append(GTK_BOX(row), edit);
    gtk_box_append(GTK_BOX(opus_ui.calendar_undated), row);
}

static void draw_schedule(GtkDrawingArea *area, cairo_t *cr, int width,
                          int height, gpointer unused) {
    (void)area;
    (void)unused;
    GdkRGBA color = {0.5, 0.5, 0.5, 0.22};
    gdk_cairo_set_source_rgba(cr, &color);
    cairo_set_line_width(cr, 1);
    for (int hour = 0; hour <= 24; hour++) {
        double y = hour * OPUS_HOUR_HEIGHT + 0.5;
        cairo_move_to(cr, 0, y);
        cairo_line_to(cr, width, y);
    }
    cairo_stroke(cr);
    (void)height;
}

static gboolean target_is_button(GtkEventController *controller,
                                 double x, double y) {
    GtkWidget *widget = gtk_event_controller_get_widget(controller);
    GtkWidget *target = widget
        ? gtk_widget_pick(widget, x, y, GTK_PICK_DEFAULT)
        : NULL;
    while (target) {
        if (GTK_IS_BUTTON(target)) {
            return TRUE;
        }
        target = gtk_widget_get_parent(target);
    }
    return FALSE;
}

static void schedule_pressed(GtkGestureClick *gesture, int presses, double x,
                             double y, gpointer data) {
    (void)presses;
    (void)x;
    ScheduleDay *day = data;
    if (target_is_button(GTK_EVENT_CONTROLLER(gesture), x, y)) {
        day->pressed = FALSE;
        return;
    }
    day->press_y = CLAMP(y, 0, OPUS_DAY_HEIGHT);
    day->pressed = TRUE;
}

static void schedule_released(GtkGestureClick *gesture, int presses, double x,
                              double y, gpointer data) {
    (void)presses;
    (void)x;
    ScheduleDay *day = data;
    if (!day->pressed ||
        target_is_button(GTK_EVENT_CONTROLLER(gesture), x, y)) {
        day->pressed = FALSE;
        return;
    }
    double end_y = CLAMP(y, 0, OPUS_DAY_HEIGHT);
    OpusEventPayload event = {
        .action = "schedule-create",
        .day = day->day,
        .y0 = MIN(day->press_y, end_y),
        .y1 = MAX(day->press_y, end_y)
    };
    if (event.y1 - event.y0 < 12) {
        event.y1 = MIN(OPUS_DAY_HEIGHT, event.y0 + OPUS_HOUR_HEIGHT);
    }
    opus_send(&event);
    day->pressed = FALSE;
}

void opus_schedule_begin(const char *heading, int period, int day_count) {
    (void)day_count;
    if (heading) {
        gtk_label_set_text(GTK_LABEL(opus_ui.heading), heading);
    }
    opus_ui.schedule_period = CLAMP(period, 0, 1);
    GtkWidget *view = opus_ui.views[2];
    gtk_box_append(GTK_BOX(view),
                   view_toolbar("schedule-period", "schedule-nav",
                                opus_ui.schedule_period, FALSE));
    GtkWidget *scroll = gtk_scrolled_window_new();
    gtk_widget_set_hexpand(scroll, TRUE);
    gtk_widget_set_vexpand(scroll, TRUE);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),
                                   GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    GtkWidget *board = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    GtkWidget *gutter = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_set_size_request(gutter, 56, -1);
    gtk_widget_set_margin_top(gutter, 28);
    for (int hour = 0; hour < 24; hour++) {
        char label[16];
        g_snprintf(label, sizeof(label), "%d:00", hour);
        GtkWidget *tick = opus_label(label);
        gtk_widget_add_css_class(tick, "opus-schedule-gutter");
        gtk_widget_add_css_class(tick, "dim-label");
        gtk_widget_set_size_request(tick, 50, OPUS_HOUR_HEIGHT);
        gtk_label_set_xalign(GTK_LABEL(tick), 1.0f);
        gtk_box_append(GTK_BOX(gutter), tick);
    }
    gtk_box_append(GTK_BOX(board), gutter);
    opus_ui.schedule_columns = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_box_append(GTK_BOX(board), opus_ui.schedule_columns);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), board);
    gtk_box_append(GTK_BOX(view), scroll);
    opus_ui.schedule_days = g_hash_table_new_full(g_str_hash, g_str_equal,
                                                  g_free, schedule_day_free);
}

void opus_schedule_day(const char *day, const char *label) {
    if (!opus_ui.schedule_columns || !opus_ui.schedule_days) {
        return;
    }
    GtkWidget *column = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_widget_set_size_request(column,
                                opus_ui.schedule_period == 0 ? 480 : OPUS_DAY_WIDTH,
                                -1);
    GtkWidget *heading = gtk_label_new(label ? label : "");
    gtk_widget_add_css_class(heading, "heading");
    gtk_box_append(GTK_BOX(column), heading);

    GtkWidget *fixed = gtk_fixed_new();
    gtk_widget_set_size_request(fixed,
                                opus_ui.schedule_period == 0 ? 480 : OPUS_DAY_WIDTH,
                                OPUS_DAY_HEIGHT);
    GtkWidget *grid = gtk_drawing_area_new();
    gtk_widget_set_size_request(grid,
                                opus_ui.schedule_period == 0 ? 480 : OPUS_DAY_WIDTH,
                                OPUS_DAY_HEIGHT);
    gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(grid), draw_schedule,
                                   NULL, NULL);
    gtk_fixed_put(GTK_FIXED(fixed), grid, 0, 0);

    ScheduleDay *info = g_new0(ScheduleDay, 1);
    info->fixed = fixed;
    info->day = g_strdup(day ? day : "");
    GtkGesture *gesture = gtk_gesture_click_new();
    g_signal_connect(gesture, "pressed", G_CALLBACK(schedule_pressed), info);
    g_signal_connect(gesture, "released", G_CALLBACK(schedule_released), info);
    gtk_widget_add_controller(fixed, GTK_EVENT_CONTROLLER(gesture));

    gtk_box_append(GTK_BOX(column), fixed);
    gtk_box_append(GTK_BOX(opus_ui.schedule_columns), column);
    g_hash_table_insert(opus_ui.schedule_days, g_strdup(day ? day : ""), info);
}

static void schedule_edit(GtkButton *button, gpointer unused) {
    (void)unused;
    opus_send_id("schedule-edit",
                 g_object_get_data(G_OBJECT(button), "opus-id"));
}

void opus_schedule_block(const char *id, const char *title, const char *detail,
                         const char *day, int start, int duration, int column,
                         int columns, const char *color, int is_class) {
    ScheduleDay *info = opus_ui.schedule_days
        ? g_hash_table_lookup(opus_ui.schedule_days, day)
        : NULL;
    if (!info) {
        return;
    }
    int available = opus_ui.schedule_period == 0 ? 480 : OPUS_DAY_WIDTH;
    int count = MAX(1, columns);
    int width = MAX(44, available / count - 4);
    int x = CLAMP(column, 0, count - 1) * available / count;
    int y = CLAMP(start, 0, 1440) * OPUS_HOUR_HEIGHT / 60;
    int height = MAX(26, duration * OPUS_HOUR_HEIGHT / 60);

    GtkWidget *button = gtk_button_new();
    gtk_widget_set_size_request(button, width, height);
    gtk_widget_add_css_class(button, "opus-schedule-block");
    gtk_widget_add_css_class(button, "flat");
    GdkRGBA rgba = opus_color(color);
    char *klass = g_strdup_printf("opus-block-%02x%02x%02x-%d",
                                  (int)(rgba.red * 255),
                                  (int)(rgba.green * 255),
                                  (int)(rgba.blue * 255),
                                  is_class ? 1 : 0);
    gtk_widget_add_css_class(button, klass);
    char *css = g_strdup_printf(
        "button.%s {"
        "  background: rgba(%d,%d,%d,%.2f);"
        "  color: white;"
        "  border-radius: 5px;"
        "  border: none;"
        "  padding: 4px 6px;"
        "}",
        klass,
        (int)(rgba.red * 255), (int)(rgba.green * 255), (int)(rgba.blue * 255),
        is_class ? 0.72 : 0.92);
    GtkCssProvider *provider = gtk_css_provider_new();
    gtk_css_provider_load_from_string(provider, css);
    gtk_style_context_add_provider_for_display(
        gdk_display_get_default(),
        GTK_STYLE_PROVIDER(provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);
    g_free(css);
    g_free(klass);

    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 1);
    GtkWidget *name = opus_label(title);
    gtk_label_set_ellipsize(GTK_LABEL(name), PANGO_ELLIPSIZE_END);
    gtk_box_append(GTK_BOX(box), name);
    if (detail && *detail && height >= 42) {
        GtkWidget *caption = opus_label(detail);
        gtk_box_append(GTK_BOX(box), caption);
    }
    gtk_button_set_child(GTK_BUTTON(button), box);
    gtk_widget_set_tooltip_text(button, detail);
    g_object_set_data_full(G_OBJECT(button), "opus-id", g_strdup(id), g_free);
    g_signal_connect(button, "clicked", G_CALLBACK(schedule_edit), NULL);
    gtk_fixed_put(GTK_FIXED(info->fixed), button, x, y);
}

static void rhythm_toggle(GtkButton *button, gpointer unused) {
    (void)unused;
    opus_send_id("toggle-rule",
                 g_object_get_data(G_OBJECT(button), "opus-id"));
}

static void rhythm_edit(GtkButton *button, gpointer unused) {
    (void)unused;
    opus_send_id("edit-rule",
                 g_object_get_data(G_OBJECT(button), "opus-id"));
}

void opus_rhythm_row(const char *id, const char *title, const char *detail,
                     int enabled, const char *color) {
    if (!opus_ui.rows) {
        return;
    }
    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    gtk_widget_add_css_class(row, "opus-rhythm-row");
    opus_set_identity(row, "rhythm-%s", id);
    GtkWidget *icon = gtk_image_new_from_icon_name("media-playlist-repeat-symbolic");
    gtk_widget_set_opacity(icon, enabled ? 0.85 : 0.4);
    gtk_box_append(GTK_BOX(row), icon);
    gtk_box_append(GTK_BOX(row), opus_color_dot(color, 8));
    GtkWidget *text = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_set_hexpand(text, TRUE);
    GtkWidget *name = opus_label(title);
    gtk_widget_add_css_class(name, "opus-work-title");
    gtk_box_append(GTK_BOX(text), name);
    GtkWidget *caption = opus_label(detail);
    gtk_widget_add_css_class(caption, "opus-work-meta");
    gtk_widget_add_css_class(caption, "dim-label");
    gtk_box_append(GTK_BOX(text), caption);
    gtk_box_append(GTK_BOX(row), text);

    GtkWidget *toggle = gtk_button_new_with_label(enabled ? "Pause" : "Resume");
    gtk_widget_add_css_class(toggle, "flat");
    g_object_set_data_full(G_OBJECT(toggle), "opus-id", g_strdup(id), g_free);
    opus_set_identity(toggle, "toggle-rule-%s", id);
    g_signal_connect(toggle, "clicked", G_CALLBACK(rhythm_toggle), NULL);
    gtk_box_append(GTK_BOX(row), toggle);

    GtkWidget *edit = gtk_button_new_from_icon_name("document-edit-symbolic");
    gtk_widget_add_css_class(edit, "flat");
    gtk_widget_set_tooltip_text(edit, "Edit rhythm");
    g_object_set_data_full(G_OBJECT(edit), "opus-id", g_strdup(id), g_free);
    opus_set_identity(edit, "edit-rule-%s", id);
    g_signal_connect(edit, "clicked", G_CALLBACK(rhythm_edit), NULL);
    gtk_box_append(GTK_BOX(row), edit);

    GtkWidget *remove = opus_button("Delete rhythm", "user-trash-symbolic",
                                    "delete-rule", id);
    opus_set_identity(remove, "delete-rule-%s", id);
    gtk_box_append(GTK_BOX(row), remove);
    gtk_box_append(GTK_BOX(opus_ui.rows), row);
}
