class AdminPostResource < PostResource
  columns [
    { attribute: :title, primary: true },
    { attribute: :body },
    { attribute: :user_name, label: "Owner" },
    { attribute: :created_at, label: "Created" },
    { attribute: :id, label: "ID" }
  ]

  fields [
    { attribute: :title },
    { attribute: :body, as: :text }
  ]
end
