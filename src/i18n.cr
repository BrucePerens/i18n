module I18n
  # Translation functions.

  # :nodoc:
  # This is the run-time translation function.
  def do_translate(s : String) : String
    if language_tag == CodingLanguage
      s
    else
      Translations[language_tag][s] || s
    end
  end

  # :nodoc:
  # Translate a fixed string, and check that it exists in all
  # languages that are defined in Translations, except for those
  # that have a language tag starting with "wip-". WIP means
  # work-in-progress, and those languages are not checked for completion.
  # You can set a "wip-" language tag for testing, and will see the
  # CodingLanguage where no translation exists.
  private macro translate(e, interpolated = false)
    {% if flag?(:"emit-translation-strings") %}
      # Emit the translation string, for creating new translation files.
      {% p %Q(#{e} => #{e}, \# #{(interpolated ? "Interpolated at " : "").id}#{e.filename.id}:#{e.line_number}).id %}
    {% end %}
    {% for k, v, index in Translations %}
      {% if !(k =~ /^wip-/) && Translations[k][e].nil? %}
          {% raise "No #{k} translation exists for #{e} at #{e.filename}:#{e.line_number}" %}
      {% end %}
    {% end %}
    do_translate({{e}})
  end

  # :nodoc:
  # Break an interpolated string into separate strings for translation.
  # a single white space, either leading or trailing, will be emitted without
  # translation. This keeps us from having to translate strings with leading
  # or trailing spaces, which is error-prone. Emit all of the translated pieces
  # to a string builder at run-time, and return the resulting string.
  private macro break_up(string)
    {% if string.class_name == "StringInterpolation" %}
      {% if flag?(:"emit-translation-strings") %}
        {% p %Q(Interpolated String #{string} at #{string.filename.id}:#{string.line_number}).id %}
      {% end %}
      %s = String::Builder.new;
      {% for e, index in string.expressions %}
        {% if e.class_name == "StringLiteral" %}
          {% if e.starts_with?(" ") %}
            {% if e.ends_with?(" ") %}
              {% if e == " " %}
                %s << e
              {% else %}
                %s << " " << translate({{e[1..e.size - 2]}}, true) << " "
              {% end %}
            {% else %}
              %s << " " << translate({{e[1..e.size - 1]}}, true)
            {% end %}
          {% elsif e.ends_with?(" ") %}
            %s << translate({{e[0..-2]}}, true) << " "
          {% end %}
        {% else %}
          %s << ({{e}}).to_s
        {% end %}
      {% end %}
      %s.to_s
    {% elsif string.class_name == "StringLiteral" %}
      translate({{string}});
    {% else %}
      {% raise "t(#{string}) at #{string.filename}:#{string.line_number}: the argument must be a literal string, not a variable or expression." %}
    {% end %}
  end

  # Translate a `String`, even an **interpolated string**. Check that a
  # translation for each string, into each language, exists at compile time,
  # and abort compilation with an error if one does not. Work-in-progress
  # translations can indicate that a compilation check is not desired.
  #
  # An interpolated string is broken up into fixed string segments, and these
  # are translated individually.
  #
  # The argument must be a literal string (including interpolated strings),
  # not a method, expression, or variable. This is because much of the
  # translation mechanism runs at compile-time.
  #
  # When the argument `-Demit-translation-strings` is provided to
  # `crystal build`,
  # the compiler will emit a table of all of the strings that are provided
  # as arguments to the `t()` function, possibly including duplicates.
  # These are written to `STDOUT` using the `Crystal::Macros#p` method.
  # This table can be edited into a translation file by the
  # programmer, and is intended to be used by a task for generating such
  # files with machine translation (not yet written).
  # 
  # Languages are referred to using
  # [IETF language tags](https://en.wikipedia.org/wiki/IETF_language_tag) .
  # Two common
  # language tags are "en-US" for English as spoken in the United States, and
  # "en" for English not distinguishing where it is spoken.
  #
  # Translations are defined in a `NamedTuple` called `Translations`, which
  # must exist in the program. Each
  # translation is defined as a tuple of a language tag and an inner tuple
  # containing translations into that language from the native language
  # used in the program (the "coding language"). Thus, the `Translations`
  # tuple looks like this:
  #
  # ```
  # Translations = { # Assuming the coding language tag is "en-US"
  #   "en" => { # English as spoken in most places other than the USA
  #     "the color of money" => "the colour of money",
  #   }
  #   "es" => { # Spanish (not distinguishing Spain or Mexico)
  #     "the color of money" => "el color del dinero"
  #   },
  #   "es-MX" => { # Mexican Spanish
  #     "the color of money" => "el color del dinero"
  #   },
  #   "de" => { # German (not distinguishing Swiss-German, etc.)
  #     "the color of money" => "die Farbe des Geldes",
  #   }
  # }
  # ```
  #
  # A constant `CodingLanguage` must exist in the program, and is set to a
  # string indicating the language used to write the native strings. So it
  # would have the form `CodingLanguage="en-US"`. `CodingLanguage` should
  # indicate where it is spoken, thus `"en-US"` rather than `"en"`.
  # This allows, for example, a translation to correct for
  # spelling differences between US English and the English spoken in the
  # United Kingdom ("en-GB").
  #
  # A variable or method `language_tag` must exist, which is or returns a
  # string for the language tag of the present user. So, this would be of
  # the form `language_tag = "es"` for Spanish (not distinguishing Castilian
  # or Mexican Spanish).
  #
  # Work-in-progress language translations are designated by modifying their
  # language tag with a `"wip-` prefix, so that the compiler does not test
  # those translations for completion. For example, a work-in-progress
  # translation into Spanish would have the tag `"wip-es"`. To test a
  # work-in-progress translation, `language_tag` must be set to the modified
  # form. It is possible for a work-in-progress translation and a completed
  # one to exist to the same language, for example `"wip-es"` and `"es"`. This
  # allows the same source code to work with a working-but-awkward machine
  # tranlation while a human translator produces a better version. 
  # 
  # NOTE: Complications of Translation
  #
  # At some point you will be askng translators to translate your strings
  # into different languages. You will probably start with a machine
  # translation, but these can not be expected to be correct, especially
  # where interpolated strings are concerned.
  # There is not an exact one-to-one mapping of words in two languages to the
  # same meaning. Nor can you expect the order of words in a sentence to remain
  # the same, since grammars vary widely between languages.
  # Thus, a translation of an interpolated string can be awkward. The original
  # writer's assumptions about what belongs before and after any variables or
  # expressions in the string may not carry over to the grammar of the
  # translated language.
  #
  # To delve briefly into just one of the many differences between languages
  # that complicate translation:
  # Many languages like English have no grammatical gender for nouns, while
  # others gender nouns male and female, male female and neuter, or common
  # and neuter. Some languages group nouns into animate and inanimate forms,
  # and some include noun class modifiers which indicate several different
  # forms of a noun. Such language differences can
  # require your translator to make assumptions about what you have
  # written. The default gender is usually male, which can lead to your
  # translation being masculinized in ways you did not expect.
  macro t(string)
    (break_up({{string}}))
  end
end
