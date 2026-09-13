#include "OpusWidgets.h"
#include "OpusTheme.h"

static void free_course_time_row(gpointer data) {
    OpusCourseTimeRow *row = data;
    if (!row) {
        return;
    }
    g_free(row->id);
    g_free(row);
}

static const char *help_titles[] = {
    "Capture a task",
    "Plan your work",
    "Track textbook notes",
    "Use the calendars",
    "Repeat only what you need",
    NULL
};

static const char *help_texts[] = {
    "Press Ctrl+N or use Add a task, type a title, and press Return. Inbox holds tasks that do not belong to a list.",
    "Create your own lists from the sidebar. Today brings together upcoming and overdue work. Open a task to change its list or dates; use its checkbox when it is done.",
    "Choose Progress when creating a task. Set the page range, then enter your last-read page as you work. Open the task for its pace suggestion.",
    "Calendar shows dated tasks and assessments. Click a day to add an item. Schedule is for timed events and class blocks; configure class times by editing a list.",
    "Rhythm repeats work on the days you choose. Create a rule, select its days, and adjust or remove it whenever your routine changes.",
    NULL
};

static GtkWidget *notes_from_scroll(GtkWidget *scroll) {
    GtkWidget *child = gtk_scrolled_window_get_child(GTK_SCROLLED_WINDOW(scroll));
    return child ? child : scroll;
}

static int weekday_mask_from_csv(const char *csv) {
    int mask = 0;
    if (!csv || !*csv) {
        return mask;
    }
    gchar **parts = g_strsplit(csv, ",", -1);
    for (gchar **part = parts; part && *part; part++) {
        int day = (int)g_ascii_strtoll(*part, NULL, 10);
        if (day >= 1 && day <= 7) {
            mask |= (1 << day);
        }
    }
    g_strfreev(parts);
    return mask;
}

static char *weekday_csv_from_box(GtkWidget *box) {
    GString *csv = g_string_new("");
    GtkWidget *child = gtk_widget_get_first_child(box);
    while (child) {
        if (GTK_IS_CHECK_BUTTON(child) &&
            gtk_check_button_get_active(GTK_CHECK_BUTTON(child))) {
            int day = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(child), "opus-day"));
            if (csv->len) {
                g_string_append_c(csv, ',');
            }
            g_string_append_printf(csv, "%d", day);
        }
        child = gtk_widget_get_next_sibling(child);
    }
    return g_string_free(csv, FALSE);
}

static void lift_current_to_start(void) {
    if (!opus_ui.editor_start || !opus_ui.editor_current) {
        return;
    }
    int start = (int)gtk_spin_button_get_value(
        GTK_SPIN_BUTTON(opus_ui.editor_start));
    int current = (int)gtk_spin_button_get_value(
        GTK_SPIN_BUTTON(opus_ui.editor_current));
    if (current < start) {
        gtk_spin_button_set_value(GTK_SPIN_BUTTON(opus_ui.editor_current), start);
    }
}

static void start_page_changed(GtkSpinButton *spin, gpointer unused) {
    (void)spin;
    (void)unused;
    lift_current_to_start();
}

static void kind_changed(GtkDropDown *dropdown, GParamSpec *spec, gpointer data) {
    (void)spec;
    (void)data;
    guint selected = gtk_drop_down_get_selected(dropdown);
    if (opus_ui.editor_progress_box) {
        gtk_widget_set_visible(opus_ui.editor_progress_box, selected == 1);
    }
    if (selected == 1) {
        lift_current_to_start();
    }
}

static void rule_kind_changed(GtkDropDown *dropdown, GParamSpec *spec,
                              gpointer unused) {
    (void)spec;
    (void)unused;
    guint selected = gtk_drop_down_get_selected(dropdown);
    if (opus_ui.editor_rule_progress_box) {
        gtk_widget_set_visible(opus_ui.editor_rule_progress_box, selected == 1);
    }
}

static void rule_schedule_toggled(GtkCheckButton *check, gpointer unused) {
    (void)unused;
    gboolean active = gtk_check_button_get_active(check);
    if (opus_ui.editor_schedule_box) {
        gtk_widget_set_visible(opus_ui.editor_schedule_box, active);
    }
}

static void repeat_toggled(GtkCheckButton *check, gpointer unused) {
    (void)unused;
    gboolean active = gtk_check_button_get_active(check);
    if (opus_ui.editor_weekday_box) {
        gtk_widget_set_visible(opus_ui.editor_weekday_box, active);
    }
    if (opus_ui.editor_repeat_end) {
        gtk_widget_set_visible(
            gtk_widget_get_parent(opus_ui.editor_repeat_end), active);
    }
}

static void save_work(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    guint kind = gtk_drop_down_get_selected(GTK_DROP_DOWN(opus_ui.editor_kind));
    char *notes = opus_text_view_text(
        notes_from_scroll(opus_ui.editor_notes));
    OpusEventPayload event = {
        .action = "save-work",
        .id = opus_ui.editor_id ? opus_ui.editor_id : "",
        .text = gtk_editable_get_text(GTK_EDITABLE(opus_ui.editor_title)),
        .day = gtk_editable_get_text(GTK_EDITABLE(opus_ui.editor_day)),
        .course = opus_dropdown_id(opus_ui.editor_list, opus_ui.editor_course_ids),
        .kind = (int)kind,
        .flags = 1,
        .payload = notes,
        .start = (int)gtk_spin_button_get_value(
            GTK_SPIN_BUTTON(opus_ui.editor_start)),
        .end = (int)gtk_spin_button_get_value(
            GTK_SPIN_BUTTON(opus_ui.editor_target)),
        .page = (int)gtk_spin_button_get_value(
            GTK_SPIN_BUTTON(opus_ui.editor_current))
    };
    opus_send(&event);
    g_free(notes);
}

static void delete_work(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    OpusEventPayload event = {
        .action = "delete-work",
        .id = opus_ui.editor_id ? opus_ui.editor_id : "",
        .kind = (int)gtk_drop_down_get_selected(GTK_DROP_DOWN(opus_ui.editor_kind))
    };
    opus_send(&event);
}

static char *serialize_class_times(void) {
    GString *payload = g_string_new("");
    if (!opus_ui.editor_time_rows) {
        return g_string_free(payload, FALSE);
    }
    for (guint i = 0; i < opus_ui.editor_time_rows->len; i++) {
        OpusCourseTimeRow *row = g_ptr_array_index(opus_ui.editor_time_rows, i);
        if (!row || !row->start || !row->end || !row->days_box) {
            continue;
        }
        if (payload->len) {
            g_string_append_c(payload, ';');
        }
        char *days = weekday_csv_from_box(row->days_box);
        /* id|start|end|days — pipe-separated so UUIDs cannot break parsing. */
        g_string_append_printf(payload, "%s|%d|%d|%s",
                               row->id ? row->id : "",
                               (int)gtk_spin_button_get_value(
                                   GTK_SPIN_BUTTON(row->start)),
                               (int)gtk_spin_button_get_value(
                                   GTK_SPIN_BUTTON(row->end)),
                               days ? days : "");
        g_free(days);
    }
    return g_string_free(payload, FALSE);
}

static void save_course(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    if (!opus_ui.editor_name || !opus_ui.editor_color) {
        return;
    }
    char *payload = serialize_class_times();
    OpusEventPayload event = {
        .action = "save-course",
        .id = opus_ui.editor_id ? opus_ui.editor_id : "",
        .text = gtk_editable_get_text(GTK_EDITABLE(opus_ui.editor_name)),
        .day = opus_color_dropdown_name(opus_ui.editor_color),
        .payload = payload,
        .flags = opus_ui.editor_list_only &&
            gtk_check_button_get_active(GTK_CHECK_BUTTON(opus_ui.editor_list_only)) ? 1 : 0
    };
    opus_send(&event);
    g_free(payload);
}

static void delete_course(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    opus_send_action("delete-list");
}

static void save_rule(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    char *days = weekday_csv_from_box(opus_ui.editor_weekday_box);
    char *notes = opus_text_view_text(
        notes_from_scroll(opus_ui.editor_notes));
    char *payload = g_strdup_printf("%s|%s|%s",
        gtk_editable_get_text(GTK_EDITABLE(opus_ui.editor_start_date)),
        gtk_editable_get_text(GTK_EDITABLE(opus_ui.editor_end_date)),
        notes);
    int flags = 0;
    if (gtk_check_button_get_active(GTK_CHECK_BUTTON(opus_ui.editor_enabled))) {
        flags |= 1;
    }
    flags |= 2;
    OpusEventPayload event = {
        .action = "save-rule",
        .id = opus_ui.editor_id ? opus_ui.editor_id : "",
        .text = gtk_editable_get_text(GTK_EDITABLE(opus_ui.editor_title)),
        .course = opus_dropdown_id(opus_ui.editor_list, opus_ui.editor_course_ids),
        .kind = (int)gtk_drop_down_get_selected(GTK_DROP_DOWN(opus_ui.editor_kind)),
        .day = days,
        .value = (int)gtk_spin_button_get_value(
            GTK_SPIN_BUTTON(opus_ui.editor_interval)),
        .flags = flags,
        .payload = payload,
        .start = (int)gtk_spin_button_get_value(
            GTK_SPIN_BUTTON(opus_ui.editor_start)),
        .end = (int)gtk_spin_button_get_value(
            GTK_SPIN_BUTTON(opus_ui.editor_target)),
        .page = (int)gtk_spin_button_get_value(
            GTK_SPIN_BUTTON(opus_ui.editor_start_minute)),
        .y0 = gtk_spin_button_get_value(GTK_SPIN_BUTTON(opus_ui.editor_duration)),
        .y1 = gtk_check_button_get_active(
            GTK_CHECK_BUTTON(opus_ui.editor_rule_schedule)) ? 1 : 0
    };
    opus_send(&event);
    g_free(days);
    g_free(notes);
    g_free(payload);
}

static void delete_rule(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    opus_send_id("delete-rule", opus_ui.editor_id ? opus_ui.editor_id : "");
}

static void save_schedule(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    int flags = 0;
    if (opus_ui.editor_exists) {
        flags |= 1;
    }
    gboolean repeat = gtk_check_button_get_active(
        GTK_CHECK_BUTTON(opus_ui.editor_repeat_enabled));
    if (repeat) {
        flags |= 2;
    }
    char *repeat_days = weekday_csv_from_box(opus_ui.editor_weekday_box);
    char *notes = opus_text_view_text(
        notes_from_scroll(opus_ui.editor_notes));
    char *payload = NULL;
    if (opus_ui.editor_has_rule && opus_ui.editor_rule_id) {
        flags |= 4;
        payload = g_strdup_printf("%s|%s|%s",
            opus_ui.editor_rule_id,
            gtk_editable_get_text(GTK_EDITABLE(opus_ui.editor_repeat_end)),
            notes);
    } else {
        payload = g_strdup_printf("%s|%s|%s",
            repeat ? repeat_days : "",
            gtk_editable_get_text(GTK_EDITABLE(opus_ui.editor_repeat_end)),
            notes);
    }
    OpusEventPayload event = {
        .action = "save-schedule",
        .id = opus_ui.editor_id ? opus_ui.editor_id : "",
        .text = gtk_editable_get_text(GTK_EDITABLE(opus_ui.editor_title)),
        .course = opus_dropdown_id(opus_ui.editor_list, opus_ui.editor_course_ids),
        .day = gtk_editable_get_text(GTK_EDITABLE(opus_ui.editor_day)),
        .start = (int)gtk_spin_button_get_value(
            GTK_SPIN_BUTTON(opus_ui.editor_start_minute)),
        .end = (int)gtk_spin_button_get_value(
            GTK_SPIN_BUTTON(opus_ui.editor_duration)),
        .flags = flags,
        .payload = payload
    };
    opus_send(&event);
    g_free(repeat_days);
    g_free(notes);
    g_free(payload);
}

static void delete_schedule(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    int scope = 0;
    if (opus_ui.editor_delete_scope) {
        scope = (int)gtk_drop_down_get_selected(
            GTK_DROP_DOWN(opus_ui.editor_delete_scope));
    }
    OpusEventPayload event = {
        .action = "delete-schedule",
        .id = opus_ui.editor_id ? opus_ui.editor_id : "",
        .value = scope
    };
    opus_send(&event);
}

static void editor_cancel_clicked(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    opus_send_action("editor-cancel");
}

static void attach_editor_actions(const char *save_action,
                                  void (*save_cb)(GtkButton *, gpointer),
                                  const char *delete_action,
                                  void (*delete_cb)(GtkButton *, gpointer)) {
    GtkWidget *actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_set_halign(actions, GTK_ALIGN_END);
    gtk_widget_set_margin_top(actions, 8);
    if (delete_action && delete_cb &&
        opus_ui.editor_id && *opus_ui.editor_id) {
        GtkWidget *remove = gtk_button_new_with_label("Delete");
        g_signal_connect(remove, "clicked", G_CALLBACK(delete_cb), NULL);
        gtk_box_append(GTK_BOX(actions), remove);
    }
    GtkWidget *cancel = gtk_button_new_with_label("Cancel");
    g_signal_connect(cancel, "clicked", G_CALLBACK(editor_cancel_clicked), NULL);
    opus_set_identity(cancel, "editor-cancel", NULL);
    gtk_box_append(GTK_BOX(actions), cancel);
    GtkWidget *save = gtk_button_new_with_label("Save");
    gtk_widget_add_css_class(save, "suggested-action");
    g_signal_connect(save, "clicked", G_CALLBACK(save_cb), NULL);
    opus_set_accessible_name(save, save_action);
    gtk_box_append(GTK_BOX(actions), save);
    GtkWidget *host =
        opus_ui.editor_actions ? opus_ui.editor_actions : opus_ui.editor_body;
    gtk_box_append(GTK_BOX(host), actions);
    opus_ui.editor_save = save_cb;
}

static void ensure_course_ids(void) {
    if (!opus_ui.editor_course_ids) {
        opus_ui.editor_course_ids = g_ptr_array_new_with_free_func(g_free);
    }
}

static void ensure_time_rows(void) {
    if (!opus_ui.editor_time_rows) {
        opus_ui.editor_time_rows =
            g_ptr_array_new_with_free_func(free_course_time_row);
    }
}

static gboolean free_course_time_row_idle(gpointer data) {
    free_course_time_row(data);
    return G_SOURCE_REMOVE;
}

static void remove_course_time(GtkButton *button, gpointer data) {
    (void)button;
    OpusCourseTimeRow *row = data;
    if (!row || !opus_ui.editor_time_rows || !opus_ui.editor_times_box) {
        return;
    }
    GtkWidget *widget = row->row;
    guint index = 0;
    if (g_ptr_array_find(opus_ui.editor_time_rows, row, &index)) {
        /* Steal the row so widgets can be destroyed before the struct is freed. */
        g_ptr_array_set_free_func(opus_ui.editor_time_rows, NULL);
        g_ptr_array_remove_index(opus_ui.editor_time_rows, index);
        g_ptr_array_set_free_func(opus_ui.editor_time_rows, free_course_time_row);
    }
    row->row = NULL;
    row->start = NULL;
    row->end = NULL;
    row->days_box = NULL;
    if (widget) {
        gtk_box_remove(GTK_BOX(opus_ui.editor_times_box), widget);
    }
    g_idle_add(free_course_time_row_idle, row);
}

static GtkWidget *course_time_row_widget(const char *id, int start, int end,
                                         const char *days_csv) {
    OpusCourseTimeRow *row = g_new0(OpusCourseTimeRow, 1);
    row->id = g_strdup(id ? id : "");
    row->row = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_add_css_class(row->row, "opus-class-time-card");
    gtk_widget_set_hexpand(row->row, TRUE);
    gtk_widget_set_halign(row->row, GTK_ALIGN_FILL);

    GtkWidget *header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *caption = opus_label("Class time");
    gtk_widget_add_css_class(caption, "opus-field-label");
    gtk_widget_set_hexpand(caption, TRUE);
    gtk_box_append(GTK_BOX(header), caption);
    GtkWidget *remove = gtk_button_new_from_icon_name("user-trash-symbolic");
    gtk_widget_add_css_class(remove, "flat");
    gtk_widget_set_tooltip_text(remove, "Remove class time");
    g_signal_connect(remove, "clicked", G_CALLBACK(remove_course_time), row);
    gtk_box_append(GTK_BOX(header), remove);
    gtk_box_append(GTK_BOX(row->row), header);

    GtkWidget *times = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
    row->start = opus_spin_int(start, 0, 1440);
    row->end = opus_spin_int(end, 0, 1440);
    GtkWidget *start_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    GtkWidget *start_label = opus_label("Starts");
    gtk_widget_add_css_class(start_label, "dim-label");
    gtk_box_append(GTK_BOX(start_box), start_label);
    gtk_box_append(GTK_BOX(start_box), row->start);
    GtkWidget *end_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    GtkWidget *end_label = opus_label("Ends");
    gtk_widget_add_css_class(end_label, "dim-label");
    gtk_box_append(GTK_BOX(end_box), end_label);
    gtk_box_append(GTK_BOX(end_box), row->end);
    gtk_box_append(GTK_BOX(times), start_box);
    gtk_box_append(GTK_BOX(times), end_box);
    gtk_box_append(GTK_BOX(row->row), times);

    row->days_box = opus_weekday_box(weekday_mask_from_csv(days_csv));
    gtk_box_append(GTK_BOX(row->row), row->days_box);

    ensure_time_rows();
    g_ptr_array_add(opus_ui.editor_time_rows, row);
    return row->row;
}

static void add_course_time(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    if (!opus_ui.editor_times_box) {
        return;
    }
    char *id = g_strdup_printf("time-%u",
                               opus_ui.editor_time_rows
                                   ? opus_ui.editor_time_rows->len
                                   : 0);
    gtk_box_append(GTK_BOX(opus_ui.editor_times_box),
                   course_time_row_widget(id, 540, 600, "2,3,4,5,6"));
    g_free(id);
}

void opus_work_editor_open(const char *id, const char *title, const char *day,
                           const char *course, int kind, int confirmed,
                           const char *notes, int start, int end, int page) {
    (void)confirmed;
    opus_editor_window_begin(id && *id ? "Edit work" : "New work", 1);
    g_free(opus_ui.editor_id);
    opus_ui.editor_id = g_strdup(id ? id : "");

    ensure_course_ids();
    opus_ui.editor_title = opus_text_entry(title);
    opus_field(opus_ui.editor_body, "Title", opus_ui.editor_title);
    opus_ui.editor_list = gtk_drop_down_new_from_strings((const char *[]) {NULL});
    opus_field(opus_ui.editor_body, "List", opus_ui.editor_list);
    opus_ui.editor_day = opus_text_entry(day);
    opus_field(opus_ui.editor_body, "Date", opus_ui.editor_day);
    opus_ui.editor_kind = opus_kind_dropdown(kind);
    g_signal_connect(opus_ui.editor_kind, "notify::selected-item",
                     G_CALLBACK(kind_changed), NULL);
    opus_field(opus_ui.editor_body, "Kind", opus_ui.editor_kind);
    opus_ui.editor_confirmed = NULL;
    opus_ui.editor_notes = opus_notes_view(notes);
    opus_field(opus_ui.editor_body, "Notes", opus_ui.editor_notes);

    opus_ui.editor_progress_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    opus_ui.editor_start = opus_spin_int(start, 0, 1000000);
    opus_ui.editor_target = opus_spin_int(end, 1, 1000000);
    opus_ui.editor_current = opus_spin_int(page, 0, 1000000);
    g_signal_connect(opus_ui.editor_start, "value-changed",
                     G_CALLBACK(start_page_changed), NULL);
    opus_field(opus_ui.editor_progress_box, "Start page", opus_ui.editor_start);
    opus_field(opus_ui.editor_progress_box, "Target page", opus_ui.editor_target);
    opus_field(opus_ui.editor_progress_box, "Current page", opus_ui.editor_current);
    gtk_widget_set_visible(opus_ui.editor_progress_box, kind == 1);
    gtk_box_append(GTK_BOX(opus_ui.editor_body), opus_ui.editor_progress_box);

    (void)course;
    attach_editor_actions("save-work", save_work, "delete-work", delete_work);
    if (opus_ui.editor_title) {
        gtk_widget_grab_focus(opus_ui.editor_title);
    } else {
        gtk_widget_grab_focus(opus_ui.editor);
    }
}

void opus_work_editor_list(const char *id, const char *name, int selected) {
    ensure_course_ids();
    opus_append_dropdown(opus_ui.editor_list, opus_ui.editor_course_ids,
                         id, name, NULL, selected);
}

void opus_course_editor_open(const char *id, const char *name,
                             const char *color, int list_only) {
    opus_editor_window_begin(id && *id ? "Edit list" : "New list", 2);
    g_free(opus_ui.editor_id);
    opus_ui.editor_id = g_strdup(id ? id : "");
    if (opus_ui.editor_time_rows) {
        g_ptr_array_unref(opus_ui.editor_time_rows);
    }
    opus_ui.editor_time_rows =
        g_ptr_array_new_with_free_func(free_course_time_row);

    opus_ui.editor_name = opus_text_entry(name);
    gtk_widget_add_css_class(opus_ui.editor_name, "opus-name-entry");
    opus_field(opus_ui.editor_body, "NAME", opus_ui.editor_name);
    opus_ui.editor_color = opus_color_dropdown(color);
    opus_field(opus_ui.editor_body, "COLOR", opus_ui.editor_color);
    opus_ui.editor_list_only = gtk_check_button_new_with_label(
        "Show only on this list");
    gtk_check_button_set_active(GTK_CHECK_BUTTON(opus_ui.editor_list_only),
                                list_only);
    gtk_widget_set_tooltip_text(
        opus_ui.editor_list_only,
        "Hide from Today, Inbox, and Calendar.");
    opus_field(opus_ui.editor_body, "VISIBILITY", opus_ui.editor_list_only);
    opus_ui.editor_times_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    opus_field(opus_ui.editor_body, "CLASS TIMES", opus_ui.editor_times_box);
    GtkWidget *add = gtk_button_new_with_label("Add class time");
    g_signal_connect(add, "clicked", G_CALLBACK(add_course_time), NULL);
    opus_set_accessible_name(add, "Add class time");
    gtk_box_append(GTK_BOX(opus_ui.editor_body), add);

    attach_editor_actions("save-course", save_course,
                          id && *id ? "delete-list" : NULL, delete_course);
    if (opus_ui.editor_name) {
        gtk_widget_grab_focus(opus_ui.editor_name);
    } else {
        gtk_widget_grab_focus(opus_ui.editor);
    }
}

void opus_course_editor_time(const char *id, int start, int end,
                             const char *days_csv) {
    if (!opus_ui.editor_times_box) {
        return;
    }
    gtk_box_append(GTK_BOX(opus_ui.editor_times_box),
                   course_time_row_widget(id, start, end, days_csv));
}

void opus_rule_editor_open(const char *id, const char *title, const char *course,
                           int work_kind, const char *days_csv, int interval,
                           const char *start_day, const char *end_day,
                           int enabled, int confirmed, const char *notes,
                           int start, int target, int start_minute,
                           int duration, int schedule) {
    (void)course;
    (void)confirmed;
    opus_editor_window_begin(id && *id ? "Edit rhythm" : "New rhythm", 3);
    g_free(opus_ui.editor_id);
    opus_ui.editor_id = g_strdup(id ? id : "");

    ensure_course_ids();
    opus_ui.editor_title = opus_text_entry(title);
    opus_field(opus_ui.editor_body, "Title", opus_ui.editor_title);
    opus_ui.editor_list = gtk_drop_down_new_from_strings((const char *[]) {NULL});
    opus_field(opus_ui.editor_body, "List", opus_ui.editor_list);
    opus_ui.editor_kind = opus_kind_dropdown(work_kind);
    g_signal_connect(opus_ui.editor_kind, "notify::selected-item",
                     G_CALLBACK(rule_kind_changed), NULL);
    opus_field(opus_ui.editor_body, "Work kind", opus_ui.editor_kind);
    opus_ui.editor_weekday_box = opus_weekday_box(weekday_mask_from_csv(days_csv));
    opus_field(opus_ui.editor_body, "Days", opus_ui.editor_weekday_box);
    opus_ui.editor_interval = opus_spin_int(interval, 1, 52);
    opus_field(opus_ui.editor_body, "Every (weeks)", opus_ui.editor_interval);
    opus_ui.editor_start_date = opus_text_entry(start_day);
    opus_field(opus_ui.editor_body, "Start date", opus_ui.editor_start_date);
    opus_ui.editor_end_date = opus_text_entry(end_day);
    opus_field(opus_ui.editor_body, "End date", opus_ui.editor_end_date);
    opus_ui.editor_enabled = gtk_check_button_new_with_label("Enabled");
    gtk_check_button_set_active(GTK_CHECK_BUTTON(opus_ui.editor_enabled), enabled);
    opus_field(opus_ui.editor_body, "Enabled", opus_ui.editor_enabled);
    opus_ui.editor_confirmed = NULL;
    opus_ui.editor_notes = opus_notes_view(notes);
    opus_field(opus_ui.editor_body, "Notes", opus_ui.editor_notes);

    opus_ui.editor_rule_progress_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    opus_ui.editor_start = opus_spin_int(start, 0, 1000000);
    opus_ui.editor_target = opus_spin_int(target, 1, 1000000);
    opus_field(opus_ui.editor_rule_progress_box, "Start page", opus_ui.editor_start);
    opus_field(opus_ui.editor_rule_progress_box, "Target page", opus_ui.editor_target);
    gtk_widget_set_visible(opus_ui.editor_rule_progress_box, work_kind == 1);
    gtk_box_append(GTK_BOX(opus_ui.editor_body), opus_ui.editor_rule_progress_box);

    opus_ui.editor_rule_schedule = gtk_check_button_new_with_label(
        "Create schedule block");
    gtk_check_button_set_active(GTK_CHECK_BUTTON(opus_ui.editor_rule_schedule),
                                schedule);
    g_signal_connect(opus_ui.editor_rule_schedule, "toggled",
                     G_CALLBACK(rule_schedule_toggled), NULL);
    gtk_box_append(GTK_BOX(opus_ui.editor_body), opus_ui.editor_rule_schedule);
    opus_ui.editor_schedule_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
    opus_ui.editor_start_minute = opus_spin_int(start_minute, 0, 1440);
    opus_ui.editor_duration = opus_spin_int(duration, 15, 1440);
    opus_field(opus_ui.editor_schedule_box, "Start minute",
               opus_ui.editor_start_minute);
    opus_field(opus_ui.editor_schedule_box, "Duration", opus_ui.editor_duration);
    gtk_widget_set_visible(opus_ui.editor_schedule_box, schedule);
    gtk_box_append(GTK_BOX(opus_ui.editor_body), opus_ui.editor_schedule_box);

    attach_editor_actions("save-rule", save_rule, "delete-rule", delete_rule);
    gtk_widget_grab_focus(opus_ui.editor);
}

void opus_rule_editor_list(const char *id, const char *name, int selected) {
    ensure_course_ids();
    opus_append_dropdown(opus_ui.editor_list, opus_ui.editor_course_ids,
                         id, name, NULL, selected);
}

void opus_schedule_editor_open(const char *id, const char *title,
                               const char *course, const char *day, int start,
                               int duration, const char *notes, int exists,
                               int has_rule, const char *repeat_end,
                               const char *rule_id) {
    (void)course;
    opus_editor_window_begin(id && *id ? "Edit schedule" : "New schedule", 4);
    g_free(opus_ui.editor_id);
    opus_ui.editor_id = g_strdup(id ? id : "");
    opus_ui.editor_exists = exists;
    opus_ui.editor_has_rule = has_rule;
    g_free(opus_ui.editor_rule_id);
    if (has_rule) {
        const char *value = (rule_id && *rule_id) ? rule_id : id;
        opus_ui.editor_rule_id = g_strdup(value ? value : "");
    } else {
        opus_ui.editor_rule_id = NULL;
    }

    ensure_course_ids();
    opus_ui.editor_title = opus_text_entry(title);
    opus_field(opus_ui.editor_body, "Title", opus_ui.editor_title);
    opus_ui.editor_list = gtk_drop_down_new_from_strings((const char *[]) {NULL});
    opus_field(opus_ui.editor_body, "List", opus_ui.editor_list);
    opus_ui.editor_day = opus_text_entry(day);
    opus_field(opus_ui.editor_body, "Day", opus_ui.editor_day);
    opus_ui.editor_start_minute = opus_spin_int(start, 0, 1440);
    opus_field(opus_ui.editor_body, "Start minute", opus_ui.editor_start_minute);
    opus_ui.editor_duration = opus_spin_int(duration, 15, 1440);
    opus_field(opus_ui.editor_body, "Duration", opus_ui.editor_duration);
    opus_ui.editor_notes = opus_notes_view(notes);
    opus_field(opus_ui.editor_body, "Notes", opus_ui.editor_notes);
    opus_ui.editor_repeat_enabled = gtk_check_button_new_with_label("Repeat");
    g_signal_connect(opus_ui.editor_repeat_enabled, "toggled",
                     G_CALLBACK(repeat_toggled), NULL);
    gtk_widget_set_visible(opus_ui.editor_repeat_enabled, !has_rule);
    gtk_box_append(GTK_BOX(opus_ui.editor_body), opus_ui.editor_repeat_enabled);
    opus_ui.editor_weekday_box = opus_weekday_box(0);
    gtk_widget_set_visible(opus_ui.editor_weekday_box, FALSE);
    gtk_widget_set_sensitive(opus_ui.editor_weekday_box, !has_rule);
    gtk_box_append(GTK_BOX(opus_ui.editor_body), opus_ui.editor_weekday_box);
    opus_ui.editor_repeat_end = opus_text_entry(repeat_end);
    opus_field(opus_ui.editor_body, "Repeat end", opus_ui.editor_repeat_end);
    gtk_widget_set_visible(gtk_widget_get_parent(opus_ui.editor_repeat_end),
                           has_rule);
    opus_ui.editor_delete_scope = gtk_drop_down_new_from_strings(
        (const char *[]) {"This event", "This and following", "All events", NULL});
    if (exists && id && *id) {
        opus_field(opus_ui.editor_body, "Delete scope",
                   opus_ui.editor_delete_scope);
    }

    attach_editor_actions("save-schedule", save_schedule,
                          exists && id && *id ? "delete-schedule" : NULL,
                          delete_schedule);
    gtk_widget_grab_focus(opus_ui.editor);
}

void opus_schedule_editor_list(const char *id, const char *name, int selected) {
    ensure_course_ids();
    opus_append_dropdown(opus_ui.editor_list, opus_ui.editor_course_ids,
                         id, name, NULL, selected);
}

static void confirm_archive_response(GObject *source, GAsyncResult *result,
                                     gpointer unused) {
    (void)unused;
    GtkAlertDialog *dialog = GTK_ALERT_DIALOG(source);
    int choice = gtk_alert_dialog_choose_finish(dialog, result, NULL);
    if (choice == 0) {
        opus_send_action("confirm-archive-delete");
    } else {
        opus_send_action("cancel-dialog");
    }
}

void opus_confirm_archive(const char *message) {
    GtkAlertDialog *dialog = gtk_alert_dialog_new("%s", message ? message : "");
    gtk_alert_dialog_set_buttons(dialog,
                                 (const char *[]) {"Delete All", "Cancel", NULL});
    gtk_alert_dialog_set_cancel_button(dialog, 1);
    gtk_alert_dialog_set_default_button(dialog, 1);
    gtk_alert_dialog_choose(dialog, GTK_WINDOW(opus_ui.window), NULL,
                            confirm_archive_response, NULL);
}

static void appearance_changed(GtkDropDown *dropdown, GParamSpec *spec,
                               gpointer unused) {
    (void)spec;
    (void)unused;
    OpusEventPayload event = {
        .action = "set-appearance",
        .value = (int)gtk_drop_down_get_selected(dropdown)
    };
    opus_send(&event);
}

static GtkWidget *appearance_row(int selected) {
    GtkWidget *dropdown = gtk_drop_down_new_from_strings(
        (const char *[]) {"System", "Light", "Dark", NULL});
    gtk_drop_down_set_selected(GTK_DROP_DOWN(dropdown),
                               (guint)CLAMP(selected, 0, 2));
    opus_set_accessible_name(dropdown, "set-appearance");
    g_signal_connect(dropdown, "notify::selected",
                     G_CALLBACK(appearance_changed), NULL);
    return dropdown;
}

static void settings_destroyed(GtkWidget *widget, gpointer unused) {
    (void)unused;
    if (widget == opus_ui.settings_dialog) {
        opus_ui.settings_dialog = NULL;
    }
}

static void settings_close(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    if (opus_ui.settings_dialog && opus_ui.overlay) {
        GtkWidget *dialog = opus_ui.settings_dialog;
        gtk_overlay_remove_overlay(GTK_OVERLAY(opus_ui.overlay), dialog);
        opus_ui.settings_dialog = NULL;
    }
}

void opus_settings_open(int appearance) {
    if (opus_ui.settings_dialog) {
        gtk_widget_set_visible(opus_ui.settings_dialog, TRUE);
        return;
    }
    opus_ui.appearance_mode = appearance;
    if (!opus_ui.overlay) {
        return;
    }

    opus_ui.settings_dialog = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_add_css_class(opus_ui.settings_dialog, "opus-overlay-dim");
    gtk_widget_set_hexpand(opus_ui.settings_dialog, TRUE);
    gtk_widget_set_vexpand(opus_ui.settings_dialog, TRUE);

    GtkWidget *center = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_set_halign(center, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(center, GTK_ALIGN_CENTER);
    gtk_widget_set_hexpand(center, TRUE);
    gtk_widget_set_vexpand(center, TRUE);

    GtkWidget *card = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_add_css_class(card, "opus-editor-card");
    gtk_widget_set_size_request(card, 420, -1);

    GtkWidget *header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    opus_margins(header, 16);
    GtkWidget *title = opus_label("Settings");
    gtk_widget_add_css_class(title, "opus-editor-title");
    gtk_widget_set_hexpand(title, TRUE);
    gtk_box_append(GTK_BOX(header), title);
    gtk_box_append(GTK_BOX(card), header);
    gtk_box_append(GTK_BOX(card), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL));

    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 14);
    opus_margins(box, 16);
    opus_field(box, "APPEARANCE", appearance_row(appearance));
    gtk_box_append(GTK_BOX(box),
                   opus_button("Export all data…", NULL, "export", NULL));
    gtk_box_append(GTK_BOX(box),
                   opus_button("Reveal database", NULL, "reveal-database", NULL));
    GtkWidget *done = gtk_button_new_with_label("Done");
    gtk_widget_add_css_class(done, "suggested-action");
    g_signal_connect(done, "clicked", G_CALLBACK(settings_close), NULL);
    opus_set_accessible_name(done, "settings-done");
    gtk_widget_set_halign(done, GTK_ALIGN_END);
    gtk_box_append(GTK_BOX(box), done);
    gtk_box_append(GTK_BOX(card), box);
    gtk_box_append(GTK_BOX(center), card);
    gtk_box_append(GTK_BOX(opus_ui.settings_dialog), center);

    g_signal_connect(opus_ui.settings_dialog, "destroy",
                     G_CALLBACK(settings_destroyed), NULL);
    gtk_overlay_add_overlay(GTK_OVERLAY(opus_ui.overlay),
                            opus_ui.settings_dialog);
}

static void help_update_content(void) {
    if (!opus_ui.help_dialog) {
        return;
    }
    GtkWidget *title = g_object_get_data(G_OBJECT(opus_ui.help_dialog),
                                         "help-title");
    GtkWidget *body = g_object_get_data(G_OBJECT(opus_ui.help_dialog),
                                        "help-body");
    GtkWidget *step = g_object_get_data(G_OBJECT(opus_ui.help_dialog),
                                       "help-step");
    GtkWidget *next = g_object_get_data(G_OBJECT(opus_ui.help_dialog),
                                        "help-next");
    if (title) {
        gtk_label_set_text(GTK_LABEL(title), help_titles[opus_ui.help_page]);
    }
    if (body) {
        gtk_label_set_text(GTK_LABEL(body), help_texts[opus_ui.help_page]);
    }
    if (step) {
        char buffer[32];
        g_snprintf(buffer, sizeof(buffer), "%d of 5",
                   opus_ui.help_page + 1);
        gtk_label_set_text(GTK_LABEL(step), buffer);
    }
    if (next) {
        gtk_button_set_label(GTK_BUTTON(next),
                             opus_ui.help_page == 4 ? "Done" : "Next");
    }
}

static void help_destroyed(GtkWidget *widget, gpointer unused) {
    (void)unused;
    if (widget == opus_ui.help_dialog) {
        opus_ui.help_dialog = NULL;
    }
}

static void help_close_clicked(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    static gboolean setup_sent = FALSE;
    if (!setup_sent) {
        opus_send_action("setup-complete");
        setup_sent = TRUE;
    }
    if (opus_ui.help_dialog) {
        gtk_window_destroy(GTK_WINDOW(opus_ui.help_dialog));
    }
}

static void help_close(void) {
    if (opus_ui.help_dialog) {
        gtk_window_destroy(GTK_WINDOW(opus_ui.help_dialog));
    }
}

static void help_next(GtkButton *button, gpointer unused) {
    (void)button;
    (void)unused;
    if (opus_ui.help_page >= 4) {
        static gboolean setup_sent = FALSE;
        if (!setup_sent) {
            opus_send_action("setup-complete");
            setup_sent = TRUE;
        }
        help_close();
        return;
    }
    opus_ui.help_page++;
    help_update_content();
}

void opus_help_open(void) {
    if (opus_ui.help_dialog) {
        gtk_window_present(GTK_WINDOW(opus_ui.help_dialog));
        return;
    }
    opus_ui.help_page = 0;
    opus_ui.help_dialog = gtk_window_new();
    gtk_window_set_title(GTK_WINDOW(opus_ui.help_dialog), "Quick start");
    gtk_widget_add_css_class(opus_ui.help_dialog, "opus-window");
    if (opus_ui.window) {
        gtk_window_set_transient_for(GTK_WINDOW(opus_ui.help_dialog),
                                     GTK_WINDOW(opus_ui.window));
    }
    gtk_window_set_modal(GTK_WINDOW(opus_ui.help_dialog), TRUE);
    gtk_window_set_default_size(GTK_WINDOW(opus_ui.help_dialog), 420, 320);
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
    gtk_widget_add_css_class(box, "opus-editor-card");
    opus_margins(box, 20);
    GtkWidget *title = opus_label(help_titles[0]);
    gtk_widget_add_css_class(title, "opus-editor-title");
    gtk_widget_add_css_class(title, "title-2");
    g_object_set_data(G_OBJECT(opus_ui.help_dialog), "help-title", title);
    gtk_box_append(GTK_BOX(box), title);
    GtkWidget *body = opus_label(help_texts[0]);
    g_object_set_data(G_OBJECT(opus_ui.help_dialog), "help-body", body);
    gtk_box_append(GTK_BOX(box), body);
    GtkWidget *footer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *step = opus_label("1 of 5");
    gtk_widget_add_css_class(step, "dim-label");
    g_object_set_data(G_OBJECT(opus_ui.help_dialog), "help-step", step);
    gtk_box_append(GTK_BOX(footer), step);
    GtkWidget *spacer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_set_hexpand(spacer, TRUE);
    gtk_box_append(GTK_BOX(footer), spacer);
    GtkWidget *close = gtk_button_new_with_label("Close");
    g_signal_connect(close, "clicked", G_CALLBACK(help_close_clicked), NULL);
    gtk_box_append(GTK_BOX(footer), close);
    GtkWidget *next = gtk_button_new_with_label("Next");
    gtk_widget_add_css_class(next, "suggested-action");
    g_object_set_data(G_OBJECT(opus_ui.help_dialog), "help-next", next);
    g_signal_connect(next, "clicked", G_CALLBACK(help_next), NULL);
    gtk_box_append(GTK_BOX(footer), next);
    gtk_box_append(GTK_BOX(box), footer);
    gtk_window_set_child(GTK_WINDOW(opus_ui.help_dialog), box);
    g_signal_connect(opus_ui.help_dialog, "destroy",
                     G_CALLBACK(help_destroyed), NULL);
    gtk_window_present(GTK_WINDOW(opus_ui.help_dialog));
}

void opus_set_appearance(int mode) {
    opus_ui.appearance_mode = CLAMP(mode, 0, 2);
    opus_theme_apply_appearance(opus_ui.appearance_mode);
}

static void export_chosen(GObject *source, GAsyncResult *result, gpointer unused) {
    (void)unused;
    GtkFileDialog *dialog = GTK_FILE_DIALOG(source);
    GFile *file = gtk_file_dialog_save_finish(dialog, result, NULL);
    if (!file) {
        return;
    }
    char *path = g_file_get_path(file);
    if (path) {
        OpusEventPayload event = {.action = "export-path", .text = path};
        opus_send(&event);
        g_free(path);
    }
    g_object_unref(file);
}

void opus_export_save(const char *suggested_name) {
    g_free(opus_ui.export_suggested_name);
    opus_ui.export_suggested_name = g_strdup(suggested_name ? suggested_name : "");
    GtkFileDialog *dialog = gtk_file_dialog_new();
    gtk_file_dialog_set_initial_name(dialog, opus_ui.export_suggested_name);
    gtk_file_dialog_save(dialog,
                         opus_ui.window ? GTK_WINDOW(opus_ui.window) : NULL,
                         NULL, export_chosen, NULL);
    g_object_unref(dialog);
}

void opus_reveal_path(const char *path) {
    if (!path || !*path) {
        return;
    }
    char *folder = g_file_test(path, G_FILE_TEST_IS_DIR)
        ? g_strdup(path)
        : g_path_get_dirname(path);
    GError *error = NULL;
    char *uri = g_filename_to_uri(folder, NULL, &error);
    if (!uri) {
        opus_error(error ? error->message : "Could not locate the database folder.");
        g_clear_error(&error);
        g_free(folder);
        return;
    }
    if (!g_app_info_launch_default_for_uri(uri, NULL, &error)) {
        opus_error(error ? error->message : "Could not open the database folder.");
    }
    g_clear_error(&error);
    g_free(uri);
    g_free(folder);
}
