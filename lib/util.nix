with builtins; let
  collectAttrFragments = successPredicate: stopPredicate: attrs: let
    _collectAttrFragments = attrs:
      concatMap (key: _collectAttrFragmentsBelowKey key attrs.${key}) (attrNames attrs)

    ;
    _collectAttrFragmentsBelowKey = key: value:
      if successPredicate value then [ [key] ]
      else if stopPredicate value then [ ]
      else if isAttrs value then
        map (fragment: if length fragment > 0 then [key] ++ fragment else [ ]) (_collectAttrFragments value)
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

    _envVarFragments = collectAttrFragments
      (value: isAttrs value && value ? "envVar")
      (value: isAttrs value && value._type or "" == "option")
      _opt.piholeConfig;
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

  extractContainerFTLEnvVars = piholeOptionDefinitions: let
    _ftl = piholeOptionDefinitions.piholeConfig.ftl;
  in map
    (name: {
      name = "FTL_${name}";
      value = _ftl.${name};
    })
    (attrNames _ftl)
  ;
}
