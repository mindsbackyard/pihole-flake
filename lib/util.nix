{
  collectAttrFragments = predicate: attrs: with builtins; let
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

  accessValueOfFragment = attrs: fragment: with builtins; let
    _accessValueOfFragment = value: fragment:
      if fragment == [] then value
      else _accessValueOfFragment (value.${head fragment}) (tail fragment)
    ;
    in _accessValueOfFragment attrs fragment
  ;
}
