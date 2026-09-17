/* Omarchy mode: {{ mode }} */
/* "TUI flat" Omarchy colors on OBS's Yami theme. Every grey is a mix between the
   theme's background and foreground, so one mapping serves dark and light themes.
   The obs-theme hook fills __OMARCHY_DARK__ from the mode above, adds the
   Omarchy font, and appends the light icon set on light themes. */

@OBSThemeMeta {
    name: 'Omarchy';
    id: 'dev.dotfiles.omarchy';
    extends: 'com.obsproject.Yami';
    author: 'dotfiles';
    dark: '__OMARCHY_DARK__';
}

@OBSThemeVars {
    --grey1: {{ mix foreground background 25% }};
    --grey2: {{ mix foreground background 45% }};
    --grey3: {{ mix background foreground 20% }};
    --grey4: {{ mix background foreground 15% }};
    --grey5: {{ mix background foreground 10% }};
    --grey6: {{ mix background foreground 6% }};
    --grey7: {{ mix background foreground 3% }};
    --grey8: {{ background }};

    --white1: {{ foreground }};
    --white2: {{ mix foreground background 12% }};
    --white3: {{ mix foreground background 20% }};
    --white4: {{ mix foreground background 35% }};
    --white5: {{ mix foreground background 50% }};

    --black1: {{ background }};
    --black2: {{ mix background foreground 10% }};
    --black3: {{ mix background foreground 25% }};
    --black4: {{ mix background foreground 40% }};
    --black5: {{ mix background foreground 55% }};

    --blue1: {{ mix accent foreground 30% }};
    --blue2: {{ mix accent foreground 15% }};
    --blue3: {{ accent }};
    --blue4: {{ mix accent background 20% }};
    --blue5: {{ mix accent background 40% }};
    --blue6: {{ mix accent background 60% }};

    --red1: {{ mix red foreground 30% }};
    --red2: {{ mix red foreground 15% }};
    --red3: {{ red }};
    --red4: {{ mix red background 20% }};
    --red5: {{ mix red background 40% }};
    --red6: {{ mix red background 60% }};

    --green1: {{ mix green foreground 30% }};
    --green2: {{ mix green foreground 15% }};
    --green3: {{ green }};
    --green4: {{ mix green background 20% }};
    --green5: {{ mix green background 40% }};
    --green6: {{ mix green background 60% }};

    --yellow1: {{ mix yellow foreground 30% }};
    --yellow2: {{ mix yellow foreground 15% }};
    --yellow3: {{ yellow }};
    --yellow4: {{ mix yellow background 20% }};
    --yellow5: {{ mix yellow background 40% }};
    --yellow6: {{ mix yellow background 60% }};

    --teal1: {{ mix cyan foreground 30% }};
    --teal2: {{ mix cyan foreground 15% }};
    --teal3: {{ cyan }};
    --teal4: {{ mix cyan background 20% }};
    --teal5: {{ mix cyan background 40% }};
    --teal6: {{ mix cyan background 60% }};

    --pink1: {{ mix magenta foreground 30% }};
    --pink2: {{ mix magenta foreground 15% }};
    --pink3: {{ magenta }};
    --pink4: {{ mix magenta background 20% }};
    --pink5: {{ mix magenta background 40% }};
    --pink6: {{ mix magenta background 60% }};

    --purple1: {{ mix magenta foreground 30% }};
    --purple2: {{ mix magenta foreground 15% }};
    --purple3: {{ magenta }};
    --purple4: {{ mix magenta background 20% }};
    --purple5: {{ mix magenta background 40% }};
    --purple6: {{ mix magenta background 60% }};

    --primary: {{ accent }};
    --primary_light: {{ mix accent foreground 15% }};
    --primary_lighter: {{ mix accent foreground 30% }};
    --primary_dark: {{ mix accent background 20% }};
    --primary_darker: {{ mix accent background 40% }};

    --warning: {{ yellow }};
    --danger: {{ red }};

    --text: {{ foreground }};
    --text_light: {{ foreground }};
    --text_inactive: {{ foreground }};
    --text_muted: {{ mix foreground background 45% }};
    --palette_link: {{ accent }};
    --palette_linkVisited: {{ accent }};
    --separator_hover: {{ foreground }};

    --bg_window: {{ background }};
    --bg_base: {{ background }};
    --bg_preview: {{ darker_background }};

    --border_color: {{ mix foreground background 40% }};

    --input_bg: {{ background }};
    --input_bg_hover: {{ selection }};
    --input_bg_focus: {{ background }};
    --input_border: {{ mix foreground background 40% }};
    --input_border_hover: {{ foreground }};
    --input_border_focus: {{ accent }};

    --button_bg: {{ background }};
    --button_bg_hover: {{ selection }};
    --button_bg_down: {{ mix selection foreground 10% }};
    --button_border: {{ mix foreground background 40% }};
    --button_border_hover: {{ foreground }};
    --button_border_focus: {{ accent }};

    --list_item_bg_selected: {{ selection }};
    --list_item_bg_hover: {{ mix selection background 40% }};

    --tab_bg: {{ background }};
    --tab_bg_down: {{ selection }};
    --tab_border_selected: {{ accent }};

    --scrollbar_bg: {{ background }};
    --scrollbar_handle: {{ mix foreground background 40% }};

    --border_radius: 0px;
    --border_radius_small: 0px;
    --border_radius_large: 0px;
}

/* TUI boxes. Yami separates areas by background contrast, which a flat surface
   removes, so docks, views, inputs and settings rows get explicit 1px borders. */

QDockWidget::title {
    border: 1px solid var(--border_color);
    border-bottom: none;
}

OBSDock > QWidget,
QAbstractItemView, QTableView, QTextEdit, QPlainTextEdit,
QGroupBox,
QMenu, QToolTip,
QScrollBar,
.frame-notice, .dialog-frame,
#previewXContainer, #previewScalingMode, #previewYScrollBar,
QLineEdit, QComboBox, QSpinBox, QDoubleSpinBox, QDateTimeEdit,
idian--ExpandButton::indicator {
    border: 1px solid var(--border_color);
}

OBSBasicStatusBar {
    border-top: 1px solid var(--border_color);
}

QLineEdit:hover, QComboBox:hover, QSpinBox:hover, QDoubleSpinBox:hover, QDateTimeEdit:hover {
    border-color: var(--text);
}

QLineEdit:focus, QComboBox:focus, QSpinBox:focus, QDoubleSpinBox:focus, QDateTimeEdit:focus {
    border-color: var(--primary);
}

QSpinBox::up-button, QDoubleSpinBox::up-button,
QDateTimeEdit::drop-down {
    border: none;
    border-left: 1px solid var(--border_color);
}

QSpinBox::down-button, QDoubleSpinBox::down-button {
    border: none;
    border-left: 1px solid var(--border_color);
    border-top: 1px solid var(--border_color);
}

idian--Row,
idian--RowFrame .btn-frame,
SourceSelectButton {
    background: var(--bg_base);
    border: 1px solid var(--border_color);
}

idian--CollapsibleRow idian--PropertiesList {
    border: 1px solid var(--border_color);
    border-top: none;
}

idian--CollapsibleRow idian--PropertiesList idian--Row {
    background-color: var(--bg_base);
}

QSlider::groove {
    background-color: var(--border_color);
}

QMainWindow::separator {
    background: var(--bg_base);
}

QMainWindow::separator:hover {
    background: var(--border_color);
}
