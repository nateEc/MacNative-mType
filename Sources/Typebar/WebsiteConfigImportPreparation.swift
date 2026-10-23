import Foundation

struct WebsiteConfigPreparedImport {
  /// Bulk-application argument before metadata setters mutate requested arrays.
  var parsed: [String: WebsiteConfigValue]
  var projection: WebsiteConfigRuntimeProjection
}

enum WebsiteConfigImportPreparation {
  /// Pure website-import preparation. Does not restore a Typebar backup, apply
  /// native fields, persist preferences, activate resources or emit UI events.
  static func prepare(_ json: String, defaults: [String: WebsiteConfigValue], orderedKeys: [String],
    schema: WebsiteConfigSchema, context: WebsiteConfigRuntimeContext) throws -> WebsiteConfigPreparedImport {
    guard let input = try WebsiteConfigJSONReader.read(json).importFields else { throw WebsiteConfigInputError.expectedObject }
    let parsed = try schema.validatingPartial(input) ?? schema.migrating(input, defaults: defaults)
    // applyConfig itself migrates again, even after the JSON entry succeeded.
    let requested = try schema.migrating(parsed, defaults: defaults)
    let projection = try WebsiteConfigRuntimeProjector.project(requested: requested, defaults: defaults,
      orderedKeys: orderedKeys, schema: schema, context: context)
    return .init(parsed: parsed, projection: projection)
  }
}
