module TicketTutorial::Tickets {
	use std::signer;
	use std::vector;
	use std::string;
	use aptos_framework::coin;
	use aptos_framework::aptos_coin::AptosCoin;
	#[test_only]
	use aptos_framework::account;
	use aptos_std::table_with_length;

	const ENO_VENUE: u64 = 0;
	const ENO_TICKETS: u64 = 1;
	const ENO_ENVELOPE: u64 = 2;
	const EINVALID_TICKET_COUNT: u64 = 3;
	const EINVALID_TICKET: u64 = 4;
	const EINVALID_PRICE: u64 = 5;
	const EMAX_SEATS: u64 = 6;
	const EINVALID_BALANCE: u64 = 7;

	struct SeatIdentifier has store, drop, copy {
		row: string::String,
		seat_number: u64,
	}

	struct ConcertTicket has store, drop {
		identifier: SeatIdentifier,
		ticket_code: string::String,
		price: u64,
	}

	struct Theater has key {
		available_tickets: table_with_length::TableWithLength<SeatIdentifier, ConcertTicket>,
		max_seats: u64,
	}

	struct TicketEnvelope has key {
		tickets: vector<ConcertTicket>,
	}

	public entry fun init_theater(vanue_owner: &signer, max_seats: u64) {
		let available_tickets = table_with_length::new<SeatIdentifier, ConcertTicket>();
		move_to<Theater>(vanue_owner, Theater {available_tickets, max_seats});
	}

	public entry fun create_ticket(
		seller: &signer,
		row: string::String,
		seat_number: u64,
		ticket_code: string::String,
		price: u64,
	) acquires Theater {
		let seller_addr = signer::address_of(seller);
		assert!(exists<Theater>(seller_addr), ENO_VENUE);
		let current_seat_count = available_ticket_count(seller_addr);
		let theater = borrow_global_mut<Theater>(seller_addr);
		assert!(current_seat_count < theater.max_seats, EMAX_SEATS);
		let identifier = SeatIdentifier { row, seat_number };
		let ticket = ConcertTicket {
			identifier,
			ticket_code,
			price,
		};
		table_with_length::add(&mut theater.available_tickets, identifier, ticket)
	}

	public entry fun purchase_ticket(buyer: &signer, seller_addr: address, row: string::String, seat_number: u64) acquires Theater, TicketEnvelope {
		let buyer_addr = signer::address_of(buyer);
		let target_seat_id = SeatIdentifier { row, seat_number };
		let theater = borrow_global_mut<Theater>(seller_addr);
		assert!(table_with_length::contains(&theater.available_tickets, target_seat_id), EINVALID_TICKET);
		let target_ticket = table_with_length::borrow(&theater.available_tickets, target_seat_id);
		coin::transfer<AptosCoin>(buyer, seller_addr, target_ticket.price);
		let ticket = table_with_length::remove(&mut theater.available_tickets, target_seat_id);
		if (!exists<TicketEnvelope>(buyer_addr)) {
			move_to(buyer, TicketEnvelope{tickets: vector::empty()});
		};
		let envelop = borrow_global_mut<TicketEnvelope>(buyer_addr);
		vector::push_back(&mut envelop.tickets, ticket);
	}

	public fun available_ticket_count(seller_addr: address): u64 acquires Theater
	{
		let theater = borrow_global<Theater>(seller_addr);
		table_with_length::length<SeatIdentifier, ConcertTicket>(&theater.available_tickets)
	}

	#[test(seller = @0x3, buyer = @0x2, aptos_framework = @aptos_framework)]
	public entry fun sender_can_buy_ticket(seller: signer, buyer: signer, aptos_framework: &signer) acquires Theater, TicketEnvelope
	{
		let seller_addr = signer::address_of(&seller);

		// initialize the theater
		init_theater(&seller, 3);
		assert!(exists<Theater>(seller_addr), ENO_VENUE);

		// create some tickets
		create_ticket(&seller, string::utf8(b"A"), 24, string::utf8(b"AB43C7F"), 15);
		create_ticket(&seller, string::utf8(b"A"), 25, string::utf8(b"AB43CFD"), 15);
		create_ticket(&seller, string::utf8(b"A"), 26, string::utf8(b"AB13C7F"), 20);

		// verify we have 3 tickets now
		assert!(available_ticket_count(seller_addr) == 3, EINVALID_TICKET_COUNT);


		// initialize & fund account to buy tickets
		account::create_account_for_test(signer::address_of(&seller));
		account::create_account_for_test(signer::address_of(&buyer));

		let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
		coin::register<AptosCoin>(&seller);
		coin::register<AptosCoin>(&buyer);

		coin::deposit(signer::address_of(&buyer), coin::mint(100, &mint_cap));
		assert!(coin::balance<AptosCoin>(signer::address_of(&buyer)) == 100, EINVALID_BALANCE);

		// buy a ticket and confirm account balance changes
		purchase_ticket(&buyer, seller_addr, string::utf8(b"A"), 24);
		assert!(exists<TicketEnvelope>(signer::address_of(&buyer)), ENO_ENVELOPE);
		assert!(coin::balance<AptosCoin>(signer::address_of(&buyer)) == 85, EINVALID_BALANCE);
		assert!(coin::balance<AptosCoin>(signer::address_of(&seller)) == 15, EINVALID_BALANCE);
		assert!(available_ticket_count(seller_addr) == 2, EINVALID_TICKET_COUNT);

		// buy a second ticket & ensure balance has changed by 20
		purchase_ticket(&buyer, seller_addr, string::utf8(b"A"), 26);
		assert!(coin::balance<AptosCoin>(signer::address_of(&buyer)) == 65, EINVALID_BALANCE);
		assert!(coin::balance<AptosCoin>(signer::address_of(&seller)) == 35, EINVALID_BALANCE);

		coin::destroy_burn_cap(burn_cap);
		coin::destroy_mint_cap(mint_cap);
	}

}