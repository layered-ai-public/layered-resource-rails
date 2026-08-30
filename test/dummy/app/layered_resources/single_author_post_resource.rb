# Exercises a single-choice combobox. Past the threshold a `multiple: false`
# select can't stay a menu of instant-apply links either, so it becomes a
# combobox — one that posts a scalar the `eq` predicate can use rather than the
# array Ransack would have to cast.
class SingleAuthorPostResource < PostResource
  filters user: { multiple: false }
end
