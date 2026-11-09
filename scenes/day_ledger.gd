class_name DayLedger
extends RefCounted
## One day's money (E4-S4; docs/design.md Economy and time): the green fees taken today and from
## how many guests, and the balance at the morning, so the day's end can tell income, upkeep
## and what was spent building (land included, net of undo refunds) apart. Main keeps it: it
## starts at each morning (start), takes each fee (add_fee) and closes at day end (close), whose
## line the next morning shows (MoneyPanel). A reader of the balance only; the builder moves it.
##
## A save made mid-day holds the balance less today's fees (Main.economy_to_save), the balance
## as of the morning the load replays from, so the replayed day's fees come in once; E4-S11: and
## what each guest paid so far (paid), so the replayed guests pay what they paid.

## The day the ledger is on, from 1 (0 before the first morning).
var day: int = 0
## Dollars taken in green fees today, and from how many guests.
var fees: int = 0
var guests: int = 0
## E4-S11: what each guest who paid today paid, in arrival order.
var paid: Array[int] = []
## The balance when today's morning started.
var morning_balance: int = 0
## True when the balance is unlimited (New sandbox): fees and upkeep are reported, nothing spent.
var unlimited: bool = false
## The last closed day's line ("" before one closes), and its net change in dollars.
var last_line: String = ""
var last_net: int = 0


## A new morning: day `d`, the balance now.
func start(d: int, balance: int, p_unlimited: bool) -> void:
	day = d
	fees = 0
	guests = 0
	paid.clear()
	morning_balance = balance
	unlimited = p_unlimited


## Forgets the last day's line too (a new course, a load).
func clear(balance: int, p_unlimited: bool) -> void:
	start(0, balance, p_unlimited)
	last_line = ""
	last_net = 0


## One guest paid `amount` at the first tee.
func add_fee(amount: int) -> void:
	fees += amount
	guests += 1
	paid.append(amount)


## Closes the day: `balance` is the balance before upkeep, `upkeep` what the day's end charges.
## Sets last_line, "Day 3: fees +$1,200 (20 guests), upkeep -$45, building -$300", and last_net.
func close(balance: int, upkeep: int) -> String:
	var building: int = 0 if unlimited else morning_balance + fees - balance
	var parts: PackedStringArray = []
	parts.append("no guests" if guests == 0 else "fees +%s (%d guest%s)" % [LandPrices.money(fees),
			guests, "" if guests == 1 else "s"])
	parts.append("no upkeep" if upkeep == 0 else "upkeep -%s" % LandPrices.money(upkeep))
	if building != 0:
		parts.append("building %s%s" % ["-" if building > 0 else "+", LandPrices.money(absi(building))])
	last_net = fees - upkeep - building
	last_line = "Day %d: %s" % [day, ", ".join(parts)]
	return last_line
