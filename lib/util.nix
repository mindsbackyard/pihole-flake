with builtins; let
  collectAttrFragments = predicate: attrs: let
    _collectAttrFragments = attrs:
      concatMap (key: _collectAttrFragmentsBelowKey key attrs.${key}) (attrNames attrs)
    ;
    _collectAttrFragmentsBelowKey = key: value:
      if predicate value then [ [key] ]
      else if isAttrs value then
        map (fragment: [key] ++ fragment) (_collectAttrFragments value)
      else [ ]
    ;
    in _collectAttrFragments attrs
  ;

  accessValueOfFragment = attrs: fragment: let
    _accessValueOfFragment = value: fragment:
      if fragment == [] then value
      else _accessValueOfFragment (value.${head fragment}) (tail fragment)
    ;
    in _accessValueOfFragment attrs fragment
  ;

  toEnvValue = value:
    if isBool value then (if value then "true" else "false")
    else if isList value then "[${concatStringSep ";" value}]"
    else value
  ;

in {
  extractContainerEnvVars = piholeOptionDeclarations: piholeOptionDefinitions: let
    _opt = piholeOptionDeclarations;
    _cfg = piholeOptionDefinitions;

    _envVarFragments = collectAttrFragments (value: isAttrs value && value ? "envVar") _opt.piholeConfig;
    in filter
      (envVar: envVar.value != null)
      (map
        (fragment: {
          name = getAttr "envVar" (accessValueOfFragment _opt.piholeConfig fragment);
          value = toEnvValue (accessValueOfFragment _cfg.piholeConfig fragment);
        })
        _envVarFragments
      )
  ;
}
