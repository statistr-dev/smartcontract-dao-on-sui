module statistr::statistr {
    use std::option;
    use std::string::String;
    // use sui::coin;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::url;
    use sui::object::{Self, ID, UID};
    use sui::clock::{Self, Clock};
    // use sui::event;
    use std::vector;
    use sui::balance::{Self, Balance};



    // Errors define 
    const NOT_TEAMMEMBER: u64 = 1;
    const NOT_OWNER: u64 = 2;
    const LOSE_THE_RIGHT_TO_VOTE : u64 = 3;
    // const NOT_STARTED: u64 = 2;
    // const MAX_CAP_REACHED: u64 = 3;
    // const OWNER_ONLY: u64 = 4; 

    const TIER_0_POINTS : u64 = 0;
    const TIER_1_POINTS : u64 = 100000;
    const TIER_2_POINTS : u64 = 1000000;
    const TIER_3_POINTS : u64 = 10000000;
    const TIER_4_POINTS : u64 = 100000000;

    struct STATISTR has drop {}

    struct CONTRACT_MEMORY has key, store {
        id: UID,
        owner: address,
        team_member: vector<address>,
        default_reward: u64,
        proposer_rate_reward: u64,
        max_rate: u64,
        voting_time: u64,
        min_number_of_votes: u64,
        reward_balance: Balance<STATISTR>,
        stake_balance: Balance<STATISTR>
    }

    struct USER_PROFILE has key, store {
        id: UID,
        owner: address,
        stake_vol: u64,
        str_point: u64
    }
    struct STAKE_TICKET has key, store {
        id: UID,
        owner: address,
        balance: u64,
        created_at: u64
    }

    struct HOLD_TICKET has key, store {
        id: UID,
        owner: address,
        balance: Balance<STATISTR>,
        created_at: u64
    }

    struct PROPOSAL has key, store {
        id: UID,
        statistr_id: String,
        creator: address, 
        hash: String,
        created_at: u64,
        precheck_st: bool,
        publish_at: u64,
        accept: u64,
        reject: u64,
        reward: u64,
        voters: vector<address>
    }
    struct VOTES has key, store {
        id: UID,
        proposal_id: ID,
        statistr_id: String,
        created_at: u64,
        vote_weight: u64,
        vote_type: bool,
        claimed: bool
    }
    public entry fun setTeamMember(contract_memory: &mut CONTRACT_MEMORY, _team_member_list: vector<address>, ctx: &mut TxContext){
        assert!(contract_memory.owner == tx_context::sender(ctx), NOT_OWNER);
        contract_memory.team_member = _team_member_list;
    }
    // Check if an address is team member
    public fun isTeamMember(contract_memory: &CONTRACT_MEMORY, address: address): bool {
        vector::contains(&contract_memory.team_member, &address)
    }
    public fun inListOfVoters(proposal: &PROPOSAL, address: address): bool {
        vector::contains(&proposal.voters, &address)
    }

    fun init(witness: STATISTR, ctx: &mut TxContext) {
       
        let (treasury, metadata) = coin::create_currency(witness, 9, b"STR", b"STATISTR", b"", option::some(url::new_unsafe_from_bytes(b"https://statistr.com/ico.svg")), ctx);
        transfer::public_freeze_object(metadata);
        let contract_memory = CONTRACT_MEMORY {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            team_member: vector::empty(),
            default_reward: 100000000000000, // 100000 * 1e9,
            proposer_rate_reward: 100,
            max_rate: 1000,
            voting_time: 8640000, // 1 day
            min_number_of_votes: 100000000000000000, // 100000000 * 1e9
            reward_balance: balance::zero(),
            stake_balance: balance::zero()
        };

        // coin::mint_and_transfer(&mut treasury, 1000000000000000, object::uid_to_address(object::uid(contract_memory)), ctx);
        let reward = coin::mint(&mut treasury, 1000000000000000000, ctx);
        coin::put(&mut contract_memory.reward_balance, reward);

        transfer::share_object(contract_memory);
        coin::mint_and_transfer(&mut treasury, 1000000000000000000, tx_context::sender(ctx), ctx);
        transfer::public_transfer(treasury, tx_context::sender(ctx));
    }
    
    public entry fun propose(_statistr_id: String, _hash: String, clock: &Clock, contract_memory: &mut CONTRACT_MEMORY, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let proposal = PROPOSAL {
            id: object::new(ctx),
            statistr_id: _statistr_id,
            creator: sender,
            hash: _hash,
            created_at: clock::timestamp_ms(clock),
            precheck_st: false,
            publish_at: 0,
            accept: 0,
            reject: 0,
            reward: contract_memory.default_reward,
            voters: vector::empty()
        };
        transfer::share_object(proposal);
    }

    public entry fun precheck(contract_memory: &mut CONTRACT_MEMORY,  clock: &Clock, _proposal: &mut PROPOSAL, _precheck_st: bool, ctx: &mut TxContext){
        let sender = tx_context::sender(ctx);
        assert!(isTeamMember(contract_memory, sender), NOT_TEAMMEMBER);
        _proposal.precheck_st = _precheck_st;
        _proposal.publish_at = clock::timestamp_ms(clock);
    }
    
    public entry fun voteWithHold(contract_memory: &CONTRACT_MEMORY, _proposal: &mut PROPOSAL, _hold_ticker: &HOLD_TICKET, clock: &Clock, _vote_type: bool ,ctx: &mut TxContext){
        let current_time = clock::timestamp_ms(clock);
        let sender = tx_context::sender(ctx);

        assert!(_hold_ticker.owner == sender && current_time - _hold_ticker.created_at >= contract_memory.voting_time && balance::value(&_hold_ticker.balance)> 0, NOT_OWNER);
        assert!(!inListOfVoters(_proposal, sender), LOSE_THE_RIGHT_TO_VOTE);

        // check proposal is open
        if(_proposal.precheck_st && current_time - _proposal.publish_at < contract_memory.voting_time){
            let votes = VOTES {
                id: object::new(ctx),
                proposal_id: object::id(_proposal),
                statistr_id: _proposal.statistr_id,
                created_at: current_time,
                vote_weight: balance::value(&_hold_ticker.balance),
                vote_type: _vote_type,
                claimed: false
            };
            if(_vote_type == true){
                _proposal.accept = _proposal.accept + balance::value(&_hold_ticker.balance);
            } else {
                _proposal.reject = _proposal.reject + balance::value(&_hold_ticker.balance);
            };
            vector::push_back(&mut _proposal.voters, sender);
            transfer::transfer(votes, sender);
        }
        // if precheck_st is true and current_time - publish_at > voting time => end
        // update vote to 
        // else vote end
    }
    public entry fun voteWithStake(contract_memory: &CONTRACT_MEMORY, _proposal: &mut PROPOSAL, _stake_ticket: &STAKE_TICKET, clock: &Clock, _vote_type: bool ,ctx: &mut TxContext){
        let current_time = clock::timestamp_ms(clock);
        let sender = tx_context::sender(ctx);

        assert!(_stake_ticket.owner == sender && _stake_ticket.balance > 0, NOT_OWNER);
        assert!(!inListOfVoters(_proposal, sender), LOSE_THE_RIGHT_TO_VOTE);


        // check proposal is open
        if(_proposal.precheck_st && current_time - _proposal.publish_at < contract_memory.voting_time){
            let votes = VOTES {
                id: object::new(ctx),
                proposal_id: object::id(_proposal),
                statistr_id: _proposal.statistr_id,
                created_at: current_time,
                vote_weight: _stake_ticket.balance,
                vote_type: _vote_type,
                claimed: false
            };
            if(_vote_type == true){
                _proposal.accept = _proposal.accept + _stake_ticket.balance;
            } else {
                _proposal.reject = _proposal.reject + _stake_ticket.balance;
            };
            vector::push_back(&mut _proposal.voters, sender);
            transfer::transfer(votes, sender);
        }
        // if precheck_st is true and current_time - publish_at > voting time => end
        // update vote to 
        // else vote end
    }
    public entry fun voteWithHoldAndStake(contract_memory: &CONTRACT_MEMORY, _proposal: &mut PROPOSAL, _stake_ticket: &STAKE_TICKET, _hold_ticker: &HOLD_TICKET, clock: &Clock, _vote_type: bool ,ctx: &mut TxContext){
        let current_time = clock::timestamp_ms(clock);
        let sender = tx_context::sender(ctx);

        assert!(_hold_ticker.owner == sender && current_time - _hold_ticker.created_at >= contract_memory.voting_time && balance::value(&_hold_ticker.balance)> 0, NOT_OWNER);
        assert!(_stake_ticket.owner == sender && _stake_ticket.balance > 0, NOT_OWNER);
        assert!(!inListOfVoters(_proposal, sender), LOSE_THE_RIGHT_TO_VOTE);


        // check proposal is open
        if(_proposal.precheck_st && current_time - _proposal.publish_at < contract_memory.voting_time){
            let votes = VOTES {
                id: object::new(ctx),
                proposal_id: object::id(_proposal),
                statistr_id: _proposal.statistr_id,
                created_at: current_time,
                vote_weight: balance::value(&_hold_ticker.balance) + _stake_ticket.balance,
                vote_type: _vote_type,
                claimed: false
            };
            if(_vote_type == true){
                _proposal.accept = _proposal.accept + balance::value(&_hold_ticker.balance) + _stake_ticket.balance;
            } else {
                _proposal.reject = _proposal.reject + balance::value(&_hold_ticker.balance) + _stake_ticket.balance;
            };
            vector::push_back(&mut _proposal.voters, sender);
            transfer::transfer(votes, sender);
        }
        // if precheck_st is true and current_time - publish_at > voting time => end
        // update vote to 
        // else vote end
    }
    // public fun votingResults(_proposal: &PROPOSAL, ctx: &mut TxContext){

    // }

    public fun claimReward(contract_memory: &mut CONTRACT_MEMORY, _votes: &mut VOTES, _proposal: &PROPOSAL, clock: &Clock, ctx: &mut TxContext){
        let current_time = clock::timestamp_ms(clock);
        let sender = tx_context::sender(ctx);
        if(_votes.proposal_id == object::id(_proposal)){
            if(_proposal.precheck_st && current_time - _proposal.publish_at > contract_memory.voting_time){
                if(_votes.vote_type == (_proposal.accept > _proposal.reject) && (_proposal.accept + _proposal.reject) >= contract_memory.min_number_of_votes){
                    if(_votes.claimed == false){
                        // claim reward
                        let _reward_number = _votes.vote_weight * (80 / 100 )* _proposal.reward /  _proposal.accept ;
                        if(_votes.vote_type == false){
                            _reward_number = _votes.vote_weight * (80 / 100 )* _proposal.reward /  _proposal.reject ;
                        };
                        let reward = coin::from_balance(balance::split(&mut contract_memory.reward_balance, _reward_number), ctx);
                        transfer::public_transfer(reward, sender);
                        _votes.claimed = true;
                    }
                }
            }
        }

    }

    public entry fun stake(contract_memory: &mut CONTRACT_MEMORY,token_amount: Coin<STATISTR>, clock: &Clock,ctx: &mut TxContext){
        let sender = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        let stake = STAKE_TICKET {
            id: object::new(ctx),
            owner: sender,
            balance: coin::value(&token_amount),
            created_at: current_time
        };
        coin::put(&mut contract_memory.stake_balance, token_amount);
        transfer::public_transfer(stake, sender);
    }

    public entry fun stakeMore(contract_memory: &mut CONTRACT_MEMORY, _stake_ticket: &mut STAKE_TICKET, token_amount: Coin<STATISTR>, clock: &Clock,ctx: &mut TxContext){
        assert!(_stake_ticket.owner == tx_context::sender(ctx), NOT_OWNER);
        let sender = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        _stake_ticket.balance = _stake_ticket.balance + coin::value(&token_amount);
        coin::put(&mut contract_memory.stake_balance, token_amount);
    }

    public entry fun unstake(contract_memory: &mut CONTRACT_MEMORY,_stake_ticket: &mut STAKE_TICKET, clock: &Clock, ctx: &mut TxContext){
        assert!(_stake_ticket.owner == tx_context::sender(ctx), NOT_OWNER);
        let amount = _stake_ticket.balance;
        let split_amount = balance::split(&mut contract_memory.stake_balance, amount);
        transfer::public_transfer(coin::from_balance(split_amount, ctx), _stake_ticket.owner);
        _stake_ticket.balance = 0;
        
    }

    public entry fun confrimHold(token_amount: Coin<STATISTR>, clock: &Clock, ctx: &mut TxContext){
        let sender = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        // let amount = coin::value(&token_amount);
        let hold_ticket = HOLD_TICKET {
            id: object::new(ctx),
            owner: sender,
            balance: balance::zero(),
            created_at: current_time
        };
        
        coin::put(&mut hold_ticket.balance, token_amount);
        transfer::public_transfer(hold_ticket, sender);
    }

    public entry fun confrimHoldMore(_hold_ticker: &mut HOLD_TICKET, token_amount: Coin<STATISTR>, clock: &Clock, ctx: &mut TxContext){
        let sender = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        coin::put(&mut _hold_ticker.balance, token_amount);
        _hold_ticker.created_at = current_time;
    }
    
    public entry fun stopHolding(_hold_ticker: &mut HOLD_TICKET, ctx: &mut TxContext){
        assert!(_hold_ticker.owner == tx_context::sender(ctx), NOT_OWNER);
        let amount = balance::value(&_hold_ticker.balance);
        let split_amount = balance::split(&mut _hold_ticker.balance, amount);
        transfer::public_transfer(coin::from_balance(split_amount, ctx), _hold_ticker.owner);
        // object::delete(object::id(_hold_ticker));
    }

}
