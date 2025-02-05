# Transform Forge broadcast artifact JSON to Safe batch builder JSON format
# Expects standard Forge broadcast output with transactions array for calls (no creates)
# Will error if required fields are missing
{
  meta: {},
  transactions: [
    .transactions[] |
      {
        to: .transaction.to,
        value: .transaction.value,
        data: .transaction.input
      }
  ]
}
