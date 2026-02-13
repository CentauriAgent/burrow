// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'meeting_intelligence.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AiBackend {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiBackend);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AiBackend()';
}


}

/// @nodoc
class $AiBackendCopyWith<$Res>  {
$AiBackendCopyWith(AiBackend _, $Res Function(AiBackend) __);
}


/// Adds pattern-matching-related methods to [AiBackend].
extension AiBackendPatterns on AiBackend {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AiBackend_Ollama value)?  ollama,TResult Function( AiBackend_Claude value)?  claude,TResult Function( AiBackend_RuleBased value)?  ruleBased,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AiBackend_Ollama() when ollama != null:
return ollama(_that);case AiBackend_Claude() when claude != null:
return claude(_that);case AiBackend_RuleBased() when ruleBased != null:
return ruleBased(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AiBackend_Ollama value)  ollama,required TResult Function( AiBackend_Claude value)  claude,required TResult Function( AiBackend_RuleBased value)  ruleBased,}){
final _that = this;
switch (_that) {
case AiBackend_Ollama():
return ollama(_that);case AiBackend_Claude():
return claude(_that);case AiBackend_RuleBased():
return ruleBased(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AiBackend_Ollama value)?  ollama,TResult? Function( AiBackend_Claude value)?  claude,TResult? Function( AiBackend_RuleBased value)?  ruleBased,}){
final _that = this;
switch (_that) {
case AiBackend_Ollama() when ollama != null:
return ollama(_that);case AiBackend_Claude() when claude != null:
return claude(_that);case AiBackend_RuleBased() when ruleBased != null:
return ruleBased(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String model,  String endpoint)?  ollama,TResult Function( String apiKey,  String model)?  claude,TResult Function()?  ruleBased,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AiBackend_Ollama() when ollama != null:
return ollama(_that.model,_that.endpoint);case AiBackend_Claude() when claude != null:
return claude(_that.apiKey,_that.model);case AiBackend_RuleBased() when ruleBased != null:
return ruleBased();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String model,  String endpoint)  ollama,required TResult Function( String apiKey,  String model)  claude,required TResult Function()  ruleBased,}) {final _that = this;
switch (_that) {
case AiBackend_Ollama():
return ollama(_that.model,_that.endpoint);case AiBackend_Claude():
return claude(_that.apiKey,_that.model);case AiBackend_RuleBased():
return ruleBased();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String model,  String endpoint)?  ollama,TResult? Function( String apiKey,  String model)?  claude,TResult? Function()?  ruleBased,}) {final _that = this;
switch (_that) {
case AiBackend_Ollama() when ollama != null:
return ollama(_that.model,_that.endpoint);case AiBackend_Claude() when claude != null:
return claude(_that.apiKey,_that.model);case AiBackend_RuleBased() when ruleBased != null:
return ruleBased();case _:
  return null;

}
}

}

/// @nodoc


class AiBackend_Ollama extends AiBackend {
  const AiBackend_Ollama({required this.model, required this.endpoint}): super._();
  

 final  String model;
 final  String endpoint;

/// Create a copy of AiBackend
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiBackend_OllamaCopyWith<AiBackend_Ollama> get copyWith => _$AiBackend_OllamaCopyWithImpl<AiBackend_Ollama>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiBackend_Ollama&&(identical(other.model, model) || other.model == model)&&(identical(other.endpoint, endpoint) || other.endpoint == endpoint));
}


@override
int get hashCode => Object.hash(runtimeType,model,endpoint);

@override
String toString() {
  return 'AiBackend.ollama(model: $model, endpoint: $endpoint)';
}


}

/// @nodoc
abstract mixin class $AiBackend_OllamaCopyWith<$Res> implements $AiBackendCopyWith<$Res> {
  factory $AiBackend_OllamaCopyWith(AiBackend_Ollama value, $Res Function(AiBackend_Ollama) _then) = _$AiBackend_OllamaCopyWithImpl;
@useResult
$Res call({
 String model, String endpoint
});




}
/// @nodoc
class _$AiBackend_OllamaCopyWithImpl<$Res>
    implements $AiBackend_OllamaCopyWith<$Res> {
  _$AiBackend_OllamaCopyWithImpl(this._self, this._then);

  final AiBackend_Ollama _self;
  final $Res Function(AiBackend_Ollama) _then;

/// Create a copy of AiBackend
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? model = null,Object? endpoint = null,}) {
  return _then(AiBackend_Ollama(
model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AiBackend_Claude extends AiBackend {
  const AiBackend_Claude({required this.apiKey, required this.model}): super._();
  

 final  String apiKey;
 final  String model;

/// Create a copy of AiBackend
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiBackend_ClaudeCopyWith<AiBackend_Claude> get copyWith => _$AiBackend_ClaudeCopyWithImpl<AiBackend_Claude>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiBackend_Claude&&(identical(other.apiKey, apiKey) || other.apiKey == apiKey)&&(identical(other.model, model) || other.model == model));
}


@override
int get hashCode => Object.hash(runtimeType,apiKey,model);

@override
String toString() {
  return 'AiBackend.claude(apiKey: $apiKey, model: $model)';
}


}

/// @nodoc
abstract mixin class $AiBackend_ClaudeCopyWith<$Res> implements $AiBackendCopyWith<$Res> {
  factory $AiBackend_ClaudeCopyWith(AiBackend_Claude value, $Res Function(AiBackend_Claude) _then) = _$AiBackend_ClaudeCopyWithImpl;
@useResult
$Res call({
 String apiKey, String model
});




}
/// @nodoc
class _$AiBackend_ClaudeCopyWithImpl<$Res>
    implements $AiBackend_ClaudeCopyWith<$Res> {
  _$AiBackend_ClaudeCopyWithImpl(this._self, this._then);

  final AiBackend_Claude _self;
  final $Res Function(AiBackend_Claude) _then;

/// Create a copy of AiBackend
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? apiKey = null,Object? model = null,}) {
  return _then(AiBackend_Claude(
apiKey: null == apiKey ? _self.apiKey : apiKey // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AiBackend_RuleBased extends AiBackend {
  const AiBackend_RuleBased(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiBackend_RuleBased);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AiBackend.ruleBased()';
}


}




// dart format on
