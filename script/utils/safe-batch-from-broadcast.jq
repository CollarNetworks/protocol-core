# Transform Forge broadcast artifact JSON to Safe batch builder JSON format
# Expects standard Forge broadcast output with transactions array for calls (no creates)
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
