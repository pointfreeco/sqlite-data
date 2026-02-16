extension Result {
  var error: Failure? {
    do {
      _ = try get()
      return nil
    } catch {
      return error
    }
  }
}
