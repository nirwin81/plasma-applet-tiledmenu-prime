# Translate

## Status

|  Locale  |  Lines  | % Done|
|----------|---------|-------|
| Template |     166 |       |
| de       | 109/166 |   65% |
| es       | 111/166 |   66% |
| fa       | 115/166 |   69% |
| fi       | 111/166 |   66% |
| fr       | 114/166 |   68% |
| he       | 114/166 |   68% |
| hr       |  90/166 |   54% |
| id       |  98/166 |   59% |
| ja       | 115/166 |   69% |
| ko       | 112/166 |   67% |
| nl       | 115/166 |   69% |
| pl       | 100/166 |   60% |
| pt       |  95/166 |   57% |
| pt_BR    | 110/166 |   66% |
| ro       | 100/166 |   60% |
| ru       | 111/166 |   66% |
| sl       | 110/166 |   66% |
| tr       | 110/166 |   66% |
| zh_CN    |  87/166 |   52% |
| zh_TW    | 115/166 |   69% |


## New Translations

* Fill out [`template.pot`](template.pot) with your translations then open a [new issue](https://github.com/nirwin81/plasma-applet-tiledmenu-prime/issues/new), name the file `spanish.txt`, attach the txt file to the issue (drag and drop).

Or if you know how to make a pull request

* Copy the `template.pot` file and name it your locale's code (Eg: `en`/`de`/`fr`) with the extension `.po`. Then fill out all the `msgstr ""`.
* Your region's locale code can be found at: https://stackoverflow.com/questions/3191664/list-of-all-locales-and-their-short-codes/28357857#28357857

## Scripts

Zren's `kpac` script can easily run the `gettext` commands for you, parsing the `metadata.json` and filling out any placeholders for you. `kpac` can be [downloaded here](https://github.com/Zren/plasma-applet-lib/blob/master/kpac) and should be placed at `~/Code/plasmoid-widgetname/kpac` to edit translations at `~/Code/plasmoid-widgetname/package/translate/`.


* `python3 ./kpac i18n` will parse the `i18n()` calls in the `*.qml` files and write it to the `template.pot` file. Then it will merge any changes into the `*.po` language files. Then it converts the `*.po` files to it's binary `*.mo` version and move it to `contents/locale/...` which will bundle the translations in the `*.plasmoid` without needing the user to manually install them.
* `python3 ./kpac localetest` will convert the `.po` to the `*.mo` files then run `plasmoidviewer` (part of `plasma-sdk`).

## How it works

Since KDE Frameworks v5.37, translations can be bundled with the zipped `*.plasmoid` file downloaded from the store.

* `xgettext` extracts the messages from the source code into a `template.pot`.
* Translators copy the `template.pot` to `fr.po` to translate the French language.
* When the source code is updated, we use `msgmerge` to update the `fr.po` based on the updated `template.pot`.
* When testing or releasing the widget, we convert the `.po` files to their binary `.mo` form with `msgfmt`.

The binary `.mo` translation files are placed in `package/contents/locale/` so you may want to add `*.mo` to your `.gitignore`.

```
package/contents/locale/fr/LC_MESSAGES/plasma_applet_com.github.nirwin81.tiledmenuprime.mo
```

## Links

* https://develop.kde.org/docs/plasma/widget/translations-i18n/
* https://l10n.kde.org/stats/gui/trunk-kf5/team/fr/plasma-desktop/
* https://techbase.kde.org/Development/Tutorials/Localization/i18n_Build_Systems
* https://api.kde.org/frameworks/ki18n/html/prg_guide.html

> Version 8 of [Zren's i18n scripts](https://github.com/Zren/plasma-applet-lib).
