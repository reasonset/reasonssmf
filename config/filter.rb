# Ruby custom filter here!

FILTER = {}

FILTER["example"] = ->(m) {
  m.reject unless m.jpmail # Return User Unknown unless Japanese Mail.
  m.save if m.from.any? {|from| ["John Doe", "Ada"].any {|addr| from.include?(addr) } # Safe filter
}
