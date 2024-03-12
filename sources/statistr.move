module statistr::statistr {
    use std::option;
    use std::string::{Self, String};
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



    const SUI_CLOCK_OBJECT_ID: address = @0x6;

    const MIN_STAKE: u64 = 1000000000000;

    // Errors define 
    const NOT_AUTH: u64 = 0;
    const NOT_TEAMMEMBER: u64 = 1;
    const NOT_OWNER: u64 = 2;
    const LOSE_THE_RIGHT_TO_VOTE : u64 = 3;
    const ERROR_MINIMUM: u64 = 4;
    // const NOT_STARTED: u64 = 2;
    // const MAX_CAP_REACHED: u64 = 3;
    // const OWNER_ONLY: u64 = 4; 

    const TIER_0_POINTS : u64 = 0;
    const TIER_1_POINTS : u64 = 100000;
    const TIER_2_POINTS : u64 = 1000000;
    const TIER_3_POINTS : u64 = 10000000;
    const TIER_4_POINTS : u64 = 100000000;

    const STAKE_TIME_L1 : u64 = 60*60*24*1000*90;
    const STAKE_TIME_L2 : u64 = 60*60*24*1000*180;
    const STAKE_TIME_L3 : u64 = 60*60*24*1000*360;

    struct STATISTR has drop {}

    struct CONTRACT_MEMORY has key, store {
        id: UID,
        owner: address,
        team_member: vector<address>,
        users: vector<address>,
        statistr_ids: vector<String>,
        default_reward: u64,
        proposer_rate_reward: u64,
        max_rate: u64,
        voting_time: u64,
        min_number_of_votes: u64,
        reward_balance: Balance<STATISTR>,
        stake_balance: Balance<STATISTR>
    }

    struct DATA_MEMORY has key, store {
        id: UID,
        statistr_id: String,
        hash: String,
        num_of_proposal: u64,
        created_at: u64,
        updated_at: u64
    }

    struct USER_PROFILE has key, store {
        id: UID,
        owner: address,
        point: u64
    }
    struct STAKE_TICKET has key, store {
        id: UID,
        owner: address,
        balance: u64,
        created_at: u64,
        stake_time: u64
    }

    struct HOLD_TICKET has key, store {
        id: UID,
        owner: address,
        balance: Balance<STATISTR>,
        created_at: u64,
        updated_at: u64
    }

    struct PROPOSAL has key, store {
        id: UID,
        statistr_id: String,
        creator: address, 
        creator_claimed: bool,
        old_hash: String,
        hash: String,
        created_at: u64,
        precheck_st: bool,
        publish_at: u64,
        accept: u64,
        reject: u64,
        accept_point: u64,
        reject_point: u64,
        reward: u64,
        creator_reward_rate: u64,
        voters: vector<ID>
    }
    struct VOTES has key, store {
        id: UID,
        proposal_id: ID,
        statistr_id: String,
        created_at: u64,
        vote_weight: u64,
        reward_weight: u64,
        vote_type: bool,
        claimed: bool
    }
    public entry fun setTeamMember(contract_memory: &mut CONTRACT_MEMORY, _team_member_list: vector<address>, ctx: &mut TxContext){
        assert!(contract_memory.owner == tx_context::sender(ctx), NOT_OWNER);
        contract_memory.team_member = _team_member_list;
    }
    // Check if an address is team member
    public fun inTheTeamMemberList(contract_memory: &CONTRACT_MEMORY, address: address): bool {
        vector::contains(&contract_memory.team_member, &address)
    }
    public fun inTheUserList(contract_memory: &CONTRACT_MEMORY, address: address): bool {
        vector::contains(&contract_memory.users, &address)
    }
    public fun inTheVoterList(proposal: &PROPOSAL, id: ID): bool {
        vector::contains(&proposal.voters, &id)
    }
    public fun inTheStatistrIds(contract_memory: &CONTRACT_MEMORY, statistr_id: String) : bool {
        vector::contains(&contract_memory.statistr_ids, &statistr_id)
    }

    public fun userTier(_user_profile: &USER_PROFILE): u64 {
        let tier = 0;
        if(_user_profile.point > TIER_4_POINTS){
            tier = 200;
        } else if(_user_profile.point > TIER_3_POINTS){
            tier = 150;
        } else if(_user_profile.point > TIER_2_POINTS){
            tier = 100;
        } else if(_user_profile.point > TIER_1_POINTS){
            tier = 50;
        };
        tier
    }

    fun init(witness: STATISTR, ctx: &mut TxContext) {
       let sender = tx_context::sender(ctx);
        let (treasury, metadata) = coin::create_currency(witness, 9, b"STR", b"STATISTR", b"", option::some(url::new_unsafe_from_bytes(b"https://statistr.com/ico.svg")), ctx);
        transfer::public_freeze_object(metadata);
        let contract_memory = CONTRACT_MEMORY {
            id: object::new(ctx),
            owner: sender,
            team_member: vector::empty(),
            users: vector::empty(),
            statistr_ids: vector::empty(),
            default_reward: 100000000000000, // 100000 * 1e9,
            proposer_rate_reward: 100,
            max_rate: 1000,
            voting_time: 8640000, // 1 day
            min_number_of_votes: 100000000000000000, // 100000000 * 1e9
            reward_balance: balance::zero(),
            stake_balance: balance::zero()
        };

        // coin::mint_and_transfer(&mut treasury, 1000000000000000, object::uid_to_address(object::uid(contract_memory)), ctx);
        vector::push_back(&mut contract_memory.users, sender);

        let reward = coin::mint(&mut treasury, 1000000000000000000, ctx);
        coin::put(&mut contract_memory.reward_balance, reward);

        transfer::share_object(contract_memory);
        coin::mint_and_transfer(&mut treasury, 1000000000000000000,sender, ctx);
        transfer::public_transfer(treasury, sender);
        let user_profile = USER_PROFILE {
            id: object::new(ctx),
            owner: sender,
            point: 0
        };
        transfer::transfer(user_profile, sender);
    }
    
    public entry fun propose(_statistr_id: String, _data_memory: &mut DATA_MEMORY, clock: &Clock, contract_memory: &mut CONTRACT_MEMORY, _hash: String, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(object::id(clock) == object::id_from_address(SUI_CLOCK_OBJECT_ID), NOT_AUTH);
        assert!(inTheStatistrIds(contract_memory, _statistr_id), NOT_AUTH);
        let current_time = clock::timestamp_ms(clock);
        
        // let old_hash = "0x";
        _data_memory.hash = _hash;
        _data_memory.num_of_proposal = _data_memory.num_of_proposal + 1;

        let proposal = PROPOSAL {
            id: object::new(ctx),
            statistr_id: _statistr_id,
            creator: sender,
            creator_claimed: false,
            old_hash: _data_memory.hash,
            hash: _hash,
            created_at: current_time,
            precheck_st: false,
            publish_at: 0,
            accept: 0,
            reject: 0,
            accept_point: 0,
            reject_point: 0,
            reward: contract_memory.default_reward,
            creator_reward_rate: 100,
            voters: vector::empty()
        };
        transfer::share_object(proposal);

        if(!inTheUserList(contract_memory, sender)){
            let user_profile = USER_PROFILE {
                id: object::new(ctx),
                owner: sender,
                point: 0
            };
            transfer::transfer(user_profile, sender);
        }
    }
    public entry fun firstPropose(_statistr_id: String, clock: &Clock, contract_memory: &mut CONTRACT_MEMORY, _hash: String, ctx: &mut TxContext) {
        assert!(object::id(clock) == object::id_from_address(SUI_CLOCK_OBJECT_ID), NOT_AUTH);
        assert!(!inTheStatistrIds(contract_memory, _statistr_id), NOT_AUTH);

        let sender = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        let data_memory = DATA_MEMORY {
            id: object::new(ctx),
            statistr_id: _statistr_id,
            hash: _hash,
            num_of_proposal: 1,
            created_at: current_time,
            updated_at: current_time
        };
        
        // let old_hash = "0x";
        let proposal = PROPOSAL {
            id: object::new(ctx),
            statistr_id: _statistr_id,
            creator: sender,
            creator_claimed: false,
            old_hash:  string::utf8(b"statistr"),
            hash: _hash,
            created_at: current_time,
            precheck_st: false,
            publish_at: 0,
            accept: 0,
            reject: 0,
            accept_point: 0,
            reject_point: 0,
            reward: contract_memory.default_reward,
            creator_reward_rate: 100,
            voters: vector::empty()
        };

        vector::push_back(&mut contract_memory.statistr_ids, _statistr_id);

        transfer::share_object(proposal);
        transfer::share_object(data_memory);
        
        if(!inTheUserList(contract_memory, sender)){
            let user_profile = USER_PROFILE {
                id: object::new(ctx),
                owner: sender,
                point: 0
            };
            transfer::transfer(user_profile, sender);
        }
    }

    public entry fun precheck(contract_memory: &mut CONTRACT_MEMORY,  clock: &Clock, _proposal: &mut PROPOSAL, _precheck_st: bool, ctx: &mut TxContext){
        let sender = tx_context::sender(ctx);

        assert!(object::id(clock) == object::id_from_address(SUI_CLOCK_OBJECT_ID), NOT_AUTH);
        assert!(inTheTeamMemberList(contract_memory, sender), NOT_TEAMMEMBER);
        _proposal.precheck_st = _precheck_st;
        _proposal.publish_at = clock::timestamp_ms(clock);
    }
    
    public entry fun voteWithHold(contract_memory: &CONTRACT_MEMORY, _user_profile: &mut USER_PROFILE, _proposal: &mut PROPOSAL, _hold_ticket: &mut HOLD_TICKET, clock: &Clock, _vote_type: bool ,ctx: &mut TxContext){
        assert!(object::id(clock) == object::id_from_address(SUI_CLOCK_OBJECT_ID), NOT_AUTH);
        let current_time = clock::timestamp_ms(clock);
        let sender = tx_context::sender(ctx);


        assert!(_hold_ticket.owner == sender && current_time - _hold_ticket.created_at >= contract_memory.voting_time && balance::value(&_hold_ticket.balance)> 0, NOT_OWNER);
        assert!(!inTheVoterList(_proposal, object::id(_hold_ticket)), LOSE_THE_RIGHT_TO_VOTE);

        // check proposal is open
        if(_proposal.precheck_st && current_time - _proposal.publish_at < contract_memory.voting_time){
            let tier = userTier(_user_profile);
            let votes = VOTES {
                id: object::new(ctx),
                proposal_id: object::id(_proposal),
                statistr_id: _proposal.statistr_id,
                created_at: current_time,
                vote_weight: balance::value(&_hold_ticket.balance),
                reward_weight: balance::value(&_hold_ticket.balance) * (contract_memory.max_rate + tier)/contract_memory.max_rate,
                vote_type: _vote_type,
                claimed: false
            };
            if(_vote_type == true){
                _proposal.accept = _proposal.accept + balance::value(&_hold_ticket.balance);
                _proposal.accept_point = _proposal.accept_point + balance::value(&_hold_ticket.balance) * (contract_memory.max_rate + tier)/contract_memory.max_rate;
            } else {
                _proposal.reject = _proposal.reject + balance::value(&_hold_ticket.balance);
                _proposal.reject_point = _proposal.reject_point + balance::value(&_hold_ticket.balance) * (contract_memory.max_rate + tier)/contract_memory.max_rate;
            };
            if(current_time - _hold_ticket.updated_at > 60 * 60 * 24 * 1000){
                _hold_ticket.updated_at = current_time;
                _user_profile.point = _user_profile.point + balance::value(&_hold_ticket.balance) * 3 * (current_time - _hold_ticket.updated_at)/ (60*60*24*1000);
            };
            vector::push_back(&mut _proposal.voters, object::id(_hold_ticket));
            transfer::transfer(votes, sender);
        }
        // if precheck_st is true and current_time - publish_at > voting time => end
        // update vote to 
        // else vote end
    }
    public entry fun voteWithStake(contract_memory: &CONTRACT_MEMORY, _user_profile: &USER_PROFILE, _proposal: &mut PROPOSAL, _stake_ticket: &STAKE_TICKET, clock: &Clock, _vote_type: bool ,ctx: &mut TxContext){
        let current_time = clock::timestamp_ms(clock);
        let sender = tx_context::sender(ctx);

        assert!(object::id(clock) == object::id_from_address(SUI_CLOCK_OBJECT_ID), NOT_AUTH);
        assert!(_stake_ticket.owner == sender && _stake_ticket.balance > 0, NOT_OWNER);
        assert!(!inTheVoterList(_proposal, object::id(_stake_ticket)), LOSE_THE_RIGHT_TO_VOTE);


        // check proposal is open
        if(_proposal.precheck_st && current_time - _proposal.publish_at < contract_memory.voting_time){
            let tier = userTier(_user_profile);
            let votes = VOTES {
                id: object::new(ctx),
                proposal_id: object::id(_proposal),
                statistr_id: _proposal.statistr_id,
                created_at: current_time,
                vote_weight: _stake_ticket.balance,
                reward_weight: _stake_ticket.balance * (contract_memory.max_rate + tier)/contract_memory.max_rate,
                vote_type: _vote_type,
                claimed: false
            };
            if(_vote_type == true){
                _proposal.accept = _proposal.accept + _stake_ticket.balance;
                _proposal.accept_point = _proposal.accept_point + _stake_ticket.balance * (contract_memory.max_rate + tier)/contract_memory.max_rate;
            } else {
                _proposal.reject = _proposal.reject + _stake_ticket.balance;
                _proposal.reject_point = _proposal.reject_point + _stake_ticket.balance * (contract_memory.max_rate + tier)/contract_memory.max_rate;

            };
            vector::push_back(&mut _proposal.voters, object::id(_stake_ticket));
            transfer::transfer(votes, sender);
        }
        // if precheck_st is true and current_time - publish_at > voting time => end
        // update vote to 
        // else vote end
    }
    public entry fun voteWithHoldAndStake(contract_memory: &CONTRACT_MEMORY, _user_profile: &mut USER_PROFILE, _proposal: &mut PROPOSAL, _stake_ticket: &STAKE_TICKET, _hold_ticket: &mut HOLD_TICKET, clock: &Clock, _vote_type: bool ,ctx: &mut TxContext){

        assert!(object::id(clock) == object::id_from_address(SUI_CLOCK_OBJECT_ID), NOT_AUTH);

        let current_time = clock::timestamp_ms(clock);
        let sender = tx_context::sender(ctx);

        assert!(_hold_ticket.owner == sender && current_time - _hold_ticket.created_at >= contract_memory.voting_time && balance::value(&_hold_ticket.balance)> 0, NOT_OWNER);
        assert!(_stake_ticket.owner == sender && _stake_ticket.balance > 0, NOT_OWNER);
        assert!(!inTheVoterList(_proposal, object::id(_hold_ticket)) && !inTheVoterList(_proposal, object::id(_stake_ticket)), LOSE_THE_RIGHT_TO_VOTE);


        // check proposal is open
        if(_proposal.precheck_st && current_time - _proposal.publish_at < contract_memory.voting_time){
            let tier = userTier(_user_profile);
            let votes = VOTES {
                id: object::new(ctx),
                proposal_id: object::id(_proposal),
                statistr_id: _proposal.statistr_id,
                created_at: current_time,
                vote_weight: balance::value(&_hold_ticket.balance) + _stake_ticket.balance,
                reward_weight: (balance::value(&_hold_ticket.balance) + _stake_ticket.balance) * (contract_memory.max_rate + tier)/contract_memory.max_rate,
                vote_type: _vote_type,
                claimed: false
            };
            if(_vote_type == true){
                _proposal.accept = _proposal.accept + balance::value(&_hold_ticket.balance) + _stake_ticket.balance;
                _proposal.accept_point = _proposal.accept_point + (balance::value(&_hold_ticket.balance) + _stake_ticket.balance) * (contract_memory.max_rate + tier)/contract_memory.max_rate;
            } else {
                _proposal.reject = _proposal.reject + balance::value(&_hold_ticket.balance) + _stake_ticket.balance;
                _proposal.reject_point = _proposal.reject_point + (balance::value(&_hold_ticket.balance) + _stake_ticket.balance) * (contract_memory.max_rate + tier)/contract_memory.max_rate;
            };

            if(current_time - _hold_ticket.updated_at > 60 * 60 * 24 * 1000){
                _hold_ticket.updated_at = current_time;
                _user_profile.point = _user_profile.point + balance::value(&_hold_ticket.balance) * 3 * (current_time - _hold_ticket.updated_at)/ (60*60*24*1000);
            };


            vector::push_back(&mut _proposal.voters, object::id(_hold_ticket));
            vector::push_back(&mut _proposal.voters, object::id(_stake_ticket));
            transfer::transfer(votes, sender);
        }
        // if precheck_st is true and current_time - publish_at > voting time => end
        // update vote to 
        // else vote end
    }
    // public fun votingResults(_proposal: &PROPOSAL, ctx: &mut TxContext){

    // }

    public fun claimReward(contract_memory: &mut CONTRACT_MEMORY, _votes: &mut VOTES, _proposal: &PROPOSAL, clock: &Clock, ctx: &mut TxContext){

        assert!(object::id(clock) == object::id_from_address(SUI_CLOCK_OBJECT_ID), NOT_AUTH);
        let current_time = clock::timestamp_ms(clock);
        let sender = tx_context::sender(ctx);
        if(_votes.proposal_id == object::id(_proposal)){
            if(_proposal.precheck_st && current_time - _proposal.publish_at > contract_memory.voting_time){
                if(_votes.vote_type == (_proposal.accept > _proposal.reject) && (_proposal.accept + _proposal.reject) >= contract_memory.min_number_of_votes){
                    if(_votes.claimed == false){
                        // claim reward
                        let _reward_number = _votes.reward_weight * ((contract_memory.max_rate - _proposal.creator_reward_rate) / contract_memory.max_rate ) * _proposal.reward /  _proposal.accept_point ;
                        if(_votes.vote_type == false){
                            _reward_number = _votes.reward_weight * ((contract_memory.max_rate - _proposal.creator_reward_rate) / contract_memory.max_rate ) * _proposal.reward /  _proposal.reject_point ;
                        };
                        let reward = coin::from_balance(balance::split(&mut contract_memory.reward_balance, _reward_number), ctx);
                        transfer::public_transfer(reward, sender);
                        _votes.claimed = true;
                    }
                }
            }
        }

    }
    public fun proposerClaimReward(contract_memory: &mut CONTRACT_MEMORY, _proposal: &mut PROPOSAL, clock: &Clock, ctx: &mut TxContext){

        assert!(object::id(clock) == object::id_from_address(SUI_CLOCK_OBJECT_ID), NOT_AUTH);
        let current_time = clock::timestamp_ms(clock);
        let sender = tx_context::sender(ctx);
        if(_proposal.creator == sender){
            if(_proposal.precheck_st && current_time - _proposal.publish_at > contract_memory.voting_time){
                if(_proposal.accept > _proposal.reject && (_proposal.accept + _proposal.reject) >= contract_memory.min_number_of_votes){
                    if(_proposal.creator_claimed == false){
                        // claim reward
                        let _reward_number = _proposal.creator_reward_rate * _proposal.reward /  contract_memory.max_rate ;

                        let reward = coin::from_balance(balance::split(&mut contract_memory.reward_balance, _reward_number), ctx);
                        transfer::public_transfer(reward, sender);
                        _proposal.creator_claimed = true;
                    }
                }
            }
        }

    }

    public entry fun stake(contract_memory: &mut CONTRACT_MEMORY, _user_profile: &mut USER_PROFILE, token_amount: Coin<STATISTR>, _stake_time: u64, clock: &Clock,ctx: &mut TxContext){

        assert!(object::id(clock) == object::id_from_address(SUI_CLOCK_OBJECT_ID), NOT_AUTH);
        assert!(coin::value(&token_amount) >= MIN_STAKE, ERROR_MINIMUM);

        let sender = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        let stake_time = STAKE_TIME_L1;
        let point_rate = 1;

        assert!(!inTheUserList(contract_memory, sender) || _user_profile.owner == sender, NOT_OWNER);


        if(_stake_time > STAKE_TIME_L1 && _stake_time < STAKE_TIME_L2){
            stake_time = STAKE_TIME_L2;
            point_rate = 2;
        } else if (_stake_time > STAKE_TIME_L2){
            stake_time = STAKE_TIME_L3;
            point_rate = 3;
        };

        let stake = STAKE_TICKET {
            id: object::new(ctx),
            owner: sender,
            balance: coin::value(&token_amount),
            created_at: current_time,
            stake_time: stake_time
        };
        if(!inTheUserList(contract_memory, sender)){
            let user_profile = USER_PROFILE {
                id: object::new(ctx),
                owner: sender,
                point: point_rate * stake.balance
            };
            transfer::transfer(user_profile, sender);
        } else {
            _user_profile.point = _user_profile.point + point_rate * stake.balance;
        };

        coin::put(&mut contract_memory.stake_balance, token_amount);
        transfer::transfer(stake, sender);

    }

    public entry fun stakeMore(contract_memory: &mut CONTRACT_MEMORY, _user_profile: &mut USER_PROFILE, _stake_ticket: &mut STAKE_TICKET, token_amount: Coin<STATISTR>, clock: &Clock,ctx: &mut TxContext){

        assert!(object::id(clock) == object::id_from_address(SUI_CLOCK_OBJECT_ID), NOT_AUTH);
        assert!(coin::value(&token_amount) >= MIN_STAKE, ERROR_MINIMUM);

        assert!(_stake_ticket.owner == tx_context::sender(ctx), NOT_OWNER);
        let sender = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        _stake_ticket.balance = _stake_ticket.balance + coin::value(&token_amount);
        _stake_ticket.created_at = current_time;

        let _stake_time = _stake_ticket.stake_time;
        let point_rate = 1;
        if(_stake_time > STAKE_TIME_L1 && _stake_time < STAKE_TIME_L2){
            _stake_time = STAKE_TIME_L2;
            point_rate = 2;
        } else if (_stake_time > STAKE_TIME_L2){
            _stake_time = STAKE_TIME_L3;
            point_rate = 3;
        };
        _user_profile.point = _user_profile.point + point_rate * coin::value(&token_amount);

        coin::put(&mut contract_memory.stake_balance, token_amount);
    }

    public entry fun unstake(contract_memory: &mut CONTRACT_MEMORY,_stake_ticket: &mut STAKE_TICKET, clock: &Clock, ctx: &mut TxContext){

        assert!(object::id(clock) == object::id_from_address(SUI_CLOCK_OBJECT_ID), NOT_AUTH);

        let current_time = clock::timestamp_ms(clock);

        assert!(_stake_ticket.owner == tx_context::sender(ctx) && current_time - _stake_ticket.created_at > _stake_ticket.stake_time, NOT_OWNER);
        let amount = _stake_ticket.balance;
        let split_amount = balance::split(&mut contract_memory.stake_balance, amount);
        transfer::public_transfer(coin::from_balance(split_amount, ctx), _stake_ticket.owner);
        _stake_ticket.balance = 0;
        
    }

    public entry fun confirmHold(contract_memory: &CONTRACT_MEMORY, token_amount: Coin<STATISTR>, clock: &Clock, ctx: &mut TxContext){

        assert!(object::id(clock) == object::id_from_address(SUI_CLOCK_OBJECT_ID), NOT_AUTH);
        assert!(coin::value(&token_amount) >= MIN_STAKE, ERROR_MINIMUM);

        let sender = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // let amount = coin::value(&token_amount);
        let hold_ticket = HOLD_TICKET {
            id: object::new(ctx),
            owner: sender,
            balance: balance::zero(),
            created_at: current_time,
            updated_at: current_time
        };
        
        coin::put(&mut hold_ticket.balance, token_amount);
        transfer::transfer(hold_ticket, sender);

        if(!inTheUserList(contract_memory, sender)){
            let user_profile = USER_PROFILE {
                id: object::new(ctx),
                owner: sender,
                point: 0
            };
            transfer::transfer(user_profile, sender);
        }
    }

    public entry fun confirmHoldMore(_hold_ticket: &mut HOLD_TICKET, token_amount: Coin<STATISTR>, clock: &Clock, ctx: &mut TxContext){

        assert!(object::id(clock) == object::id_from_address(SUI_CLOCK_OBJECT_ID), NOT_AUTH);
        assert!(coin::value(&token_amount) >= MIN_STAKE, ERROR_MINIMUM);

        let sender = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        coin::put(&mut _hold_ticket.balance, token_amount);
        _hold_ticket.created_at = current_time;
    }
    
    public entry fun stopHolding(_hold_ticket: &mut HOLD_TICKET, ctx: &mut TxContext){
        assert!(_hold_ticket.owner == tx_context::sender(ctx), NOT_OWNER);
        let amount = balance::value(&_hold_ticket.balance);
        let split_amount = balance::split(&mut _hold_ticket.balance, amount);
        transfer::public_transfer(coin::from_balance(split_amount, ctx), _hold_ticket.owner);
        // object::delete(object::id(_hold_ticket));
    }

}
