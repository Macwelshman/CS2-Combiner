enum ExportAvailability {
    static func showsExportAll(hasBaseColor: Bool, hasLOD2Sets: Bool) -> Bool {
        hasBaseColor && hasLOD2Sets
    }
}
