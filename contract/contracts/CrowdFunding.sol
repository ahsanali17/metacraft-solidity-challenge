// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.19;

/// @notice Inherits Ownable & ReentrancyGuard from OpenZeppelin
import '../node_modules/@openzeppelin/contracts/access/Ownable.sol';
import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title A crowd funding contract
/// @author Ahsan Syed
/// @custom:experimental This is an experimental contract.
contract CrowdFunding2 is Ownable, ReentrancyGuard {

    /// @notice Milestones defined by the Event Creator
    struct Milestone {
        string name;
        uint32 targetAmount;
        bool completed;
    }

    /// @notice Object that contains all of our events information
    struct CrowdFundingEvent {
        string Name;
        string Description;
        address payable EventCreator;
        EventStatus Status;
        uint FundingGoal;
        uint Deadline;
        uint EventId;
        uint totalAmountRaised;
    }

    /// @notice Represents the possible statuses of an event, 0, 1, 2
    enum EventStatus { Active, Cancelled, Completed }

    /// @notice This where we store the ID's all of our newly created ongoing events, data is accessed by the events index not the ID
    CrowdFundingEvent[] public ongoingEvents;
    // mapping from eventId to its index in the ongoingEvents array
    /// @dev Useful for finding the index of an event
    mapping(uint256 eventId => uint256 eventIndex) public eventIdToIndex;
    /// @notice Using the eventId track how much ether a user has donated to event(s)
    mapping(uint256 eventId => mapping(address contributor => uint256 donatedAmount)) public contributions;
    /// @notice Using the eventId to check if specific event is finished
    mapping(uint256 eventId => bool isFinised) public eventProgress;
    /// @notice Using the eventId retrieve the events milestone(s)
    mapping(uint256 eventId => Milestone[]) internal eventMilestones;

    /// @notice Emitted when new event is created
    event EventCreated(address indexed eventCreator, uint indexed eventId, string name);
    /// @notice Emitted when new contributions is made to specific event
    event ContributionMade(address indexed contributor, uint256 contributionAmount, uint256 indexed eventId);
    /// @notice Emitted when user withdraws contribution from event
    event ContributionRefunded(uint256 amountRefunded, address indexed contributor, uint256 indexed eventId);
    /// @notice Emitted when EventCreator changes the status of the event
    event EventStatusChanged(EventStatus currentStatus, address indexed eventCreator, uint256 indexed eventId);
    /// @notice Emitted when a specific event surpasses reaches a monetary target in its lifecycle
    event MilestoneUpdated(uint256 indexed eventId, uint256 indexed milestoneIndex, bool indexed isMilestoneCompleted);
    /// @notice Emitted when owner has claimed the total donations because event was successful
    event FundsReleasedToOwner(uint256 indexed eventId, uint256 totalAmountRaised, address eventCreator);

    /// @notice Check for letting only the event creator access a specific function in the contract
    modifier onlyEventCreator(uint eventId) {
        require(msg.sender == ongoingEvents[eventId].EventCreator, "Only the event creator can change this!");
        _;
    }
    constructor() payable {}

    /// @notice Helper function to check the events status' and if it has reached it's deadline and it's funding goal
    /// @dev Plan to reuse this function in other functions to quickly get the status
    /// @param _eventIndex Is the index of the event inside ongoingEvents
    /// @return _chosenEventStatus, a enum returns the status of the event 3 statuses: 0=Active | 1=Cancelled | 2=Completed
    function getEventStatus(uint256 _eventIndex) public view returns(EventStatus) {
        CrowdFundingEvent storage chosenEvent = _getEventDetails(_eventIndex);
        return chosenEvent.Status;
    }

    /// @notice This function creates a new event and stores it for us, emits an event and returns the eventId
    /// @dev Main function used to create events, take note of the eventId produced you will need it.
    /// @param _name The name of the crowd funded event
    /// @param _description The description to describe what this event is about
    /// @param _fundingGoalInEther The amount of ETH this event needs to be fully funded
    /// @param _durationInDays The amount of days this event will go on for, starts at the time of event being created
    /// @return eventId Is the event ID produced when a new event. This can also be queried from public function see getAllEvents() & ongoingEvents
    function createCrowdFundingEvent(
        string calldata _name,
        string calldata _description,
        uint _fundingGoalInEther,
        uint _durationInDays
    ) external returns(uint eventId) {
        // Checking that the name and description are within a certain amount of characters to reduce gas costs.
        require(bytes(_name).length <= 100, "Name should be less than or equal to 100 characters");
        require(bytes(_description).length <= 1000, "Description should be less than or equal to 1000 characters");
        // Validating the funding goal range, adds a cap to amount of eth 1 event can raise
        require(_fundingGoalInEther != 0 ether && _fundingGoalInEther <= 1000 ether, "Funding goal should be between 1 and 10,000 ether");
        // Validating the duration in days, adds a maximum amount of days for a crowd funding event to exist
        require(_durationInDays != 0 && _durationInDays <= 365, "Duration should be between 1 and 365 days");

        // Store the deadline, by creating a block timestamp for it
        uint _deadline = block.timestamp + (_durationInDays * 1 days);
        // Gets the total length of the ongoingEvents array and stores it as our eventId, basically a counter
        uint _eventId = ongoingEvents.length;
        // Track the new eventId in our eventIdToIndex mapping
        eventIdToIndex[_eventId] = _eventId;

        // Creates a new event
        CrowdFundingEvent memory _newEvent = CrowdFundingEvent(
            _name,
            _description,
            payable(msg.sender),
            EventStatus.Active,
            _fundingGoalInEther,
            _deadline,
            _eventId,
            0 ether
        );
        // Saves the newly created event into our array of ongoing CrowdFundedEvents
        ongoingEvents.push(_newEvent);

        // Emit event for every newly created event
        emit EventCreated(msg.sender, _eventId, _name);
        return _eventId;
    }

    /// @notice Here we will let users send money to a specific event and store that data as their contribution
    /// @dev A user can only donate to the event of their chosing with this function
    /// @param _eventId Is the ID of the event, produced during creation of event or retrieved by getAllEvents() & ongoingEvents
    function donateToEvent(uint64 _eventId) external payable nonReentrant {
        // Ensure the event has at least one milestone before allowing donations
        require(eventMilestones[_eventId].length != 0, "Event must have at least one milestone");

        // We store the current status of the event
        EventStatus statusOfCurrentEvent = getEventStatus(_eventId);
        // Before a user can transfer money to an event a check is done to ensure that the event is still active and accepting donations
        require(statusOfCurrentEvent == EventStatus.Active, "The event is not active");
        // Before a user can transfer a small check is made to ensure that this event is ongoing
        require(eventProgress[_eventId] == false, "Event has concluded as the EventOwner has claimed all the donated funds");

        // Make an update to the total donations of this event to include users donation
        ongoingEvents[_eventId].totalAmountRaised += msg.value;
        // We ensure that we keep track of the users donation based off the event they donated to, their address and the amount
        contributions[_eventId][msg.sender] += msg.value;
        // For every donation this function will check if it needs to update this events milestone(s) status' to 'completed' if the target amount was reached
        _updateMilestones(_eventId);
        // For every donation this function will only update the status if the funding goal is reached otherwise it just checks
        _updateEventStatus(_eventId);

        // Emit event for every contribution made
        emit ContributionMade(msg.sender, msg.value, _eventId);
    }

    /// @notice User can only withdraw if the event has expired (reached it's deadline) and if the funding goal was not reached
    /// @dev The logic in this function is bound to be changed to give better options for the user to withdraw
    /// @param _eventId Is the ID of the event, produced during creation of event or retrieved by getAllEvents() & ongoingEvents
    function withdrawContribution(uint64 _eventId) external nonReentrant {
        CrowdFundingEvent storage chosenEvent = _getEventDetails(_eventId);
        // Check if the funding goal has not been reached, if it has user can't take out their contribution
        require(!_isFundingGoalReached(chosenEvent), "Funding goal has been reached!");
        // Before a user can get a refund for their donation -a check is done to ensure that the event is still ongoing, if it is not then the event owner has withdrawn all the funds for this specific event from the contract.
        require(eventProgress[_eventId] == false, "Event has concluded as the EventOwner has claimed all the donated funds");

        // Get the users contributed amount from the specified event
        uint256 contributedAmount = contributions[_eventId][msg.sender];
        // Chcek to see that their contribution is more than 0
        require(contributedAmount != 0, "No contribution found");

        // Now we update the users contribution for this event to zero
        contributions[_eventId][msg.sender] = 0;
        // Now we subtract the withdrawal from the totalAmountRaised
        ongoingEvents[_eventId].totalAmountRaised -= contributedAmount;
        // For every donation this function will check if it needs to update this events milestone(s) status' to 'completed' if the target amount was reached
        _updateMilestones(_eventId);
        // For every donation this function will only update the status if the funding goal is reached otherwise it just checks
        _updateEventStatus(_eventId);

        // Transfer the contributed amount back to the user
        (bool sent,) = msg.sender.call{value: contributedAmount}("");
        require(sent, "Failed to send Ether");
        // Emit the contribution was refunded to contributor
        emit ContributionRefunded(contributedAmount, msg.sender, _eventId);
    }

    /// @notice This function will simply return the specified events milestones, which are essentially goalposts
    /// @dev There were a few ways to implement this, my plan was to keep it simply as possible and minimize the # of transactions for the event creator
    /// @param _eventId Is the ID of the event, produced during creation of event or retrieved by getAllEvents() & ongoingEvents
    /// @return eventMilestone[_eventId], returns the existing milestones for a specific event
    function getEventMilestones(uint64 _eventId) external view returns (Milestone[] memory) {
        return eventMilestones[_eventId];
    }

    /// @notice Get all the events that are ongoing (compeleted events are removed from memory)
    /// @dev Useful to just get all the current events that exist and display on a frontend
    /// @return ongoingEvents, a list of all the currently ongoing events
    function getAllEvents() external view returns(CrowdFundingEvent[] memory) {
        return ongoingEvents;
    }


    /// @notice This function is responsible for giving the event creator on a successfully funding event
    /// @dev Implemented this with caution and added necessary checks to ensure event creator cannot run away with funds
    /// @param _eventId Is the ID of the event, produced during creation of event or retrieved by getAllEvents() & ongoingEvents
    function releaseFundsToEventOwner(uint256 _eventId) external onlyEventCreator(_eventId) nonReentrant {
        CrowdFundingEvent storage chosenEvent = _getEventDetails(_eventId);
        require(chosenEvent.Status == EventStatus.Completed, "This event is not completed!");
        require(chosenEvent.totalAmountRaised >= chosenEvent.FundingGoal, "Funding goal has not reached!");

        // When the event has concluded, it will set it to true and not let anyone else donate to this event after event owner claims funds
        eventProgress[_eventId] = true;

        // To free up gas and also let every know the specific event is not ongoing anymore, we remove it from the list
        // We retrieve the index of the current _eventId and save it as our current index
        uint index = eventIdToIndex[_eventId];
        // We get the entire length of the ongoingEvents - 1 and store the result
        uint lastEventId = ongoingEvents.length - 1;
        // If the current event index is not the last index in ongoingEvents
        if(index != lastEventId) {
            // Then move the last event into the position of the one we just removed, order of ongoing events doesn't matter to us in this context
            ongoingEvents[index] = ongoingEvents[lastEventId];
            // Finally we also update the index in the mapping to reflect the ID swap
            eventIdToIndex[ongoingEvents[index].EventId] = index;
        }
        // Now we reduce the length of the array by one
        ongoingEvents.pop();
        // Delete the
        delete eventIdToIndex[_eventId];

        // We make a call to send all of the users donation to the event creator
        (bool sent,) = chosenEvent.EventCreator.call{value: chosenEvent.totalAmountRaised, gas: 5000}("");
        // Make sure that the transaction goes through successfully, reentrancy guard
        require(sent, "The transaction did not go through:");

        // Emit the total crowd funded balance was given to the event creator
        emit FundsReleasedToOwner(_eventId, chosenEvent.totalAmountRaised, msg.sender);
    }

    /// @notice Function to let event creators associate milestone to their event also updates milestone status automatically
    /// @param _eventId Is the ID of the event, produced during creation of event or retrieved by getAllEvents() & ongoingEvents
    /// @param _milestoneName This is the name you can give to your milestone, ex: Goal 1
    /// @param _milestoneTargetAmount This is the monotary goalpost that your aiming to reach on your way 100% successfully funded
    function addMilestone(uint32 _eventId, string calldata _milestoneName, uint32 _milestoneTargetAmount) external onlyEventCreator(_eventId) {
        // Checks to see that the eventId(also an index) is within the bounds of our ongoingEvents array. If the array has a total od just 9 items and you set eventId to 10 then you would be outside the bounds
        require(_eventId < ongoingEvents.length, "Event does not exist or has already completed!");
        // Add a upper limit to the milestones a user can create for an event to reduce dynamic data entry
        require(eventMilestones[_eventId].length < 9, "This event has reached the maximum amount of milestones allowed!");

        // Create a new milestone
        Milestone memory newMilestone = Milestone({
            name: _milestoneName,
            targetAmount: _milestoneTargetAmount,
            completed: false
        });
        // Saves the newMilestone we created and associates it with the chosen eventId
        eventMilestones[_eventId].push(newMilestone);

        // Update the completion status of all milestones for the event
        _updateMilestones(_eventId);
    }

    /// @notice Lets the event creator remove the specified milestone
    /// @dev We loop through the milestone of a specific event and remove the index we want
    /// @param _eventId Is the ID of the event, produced during creation of event or retrieved by getAllEvents() & ongoingEvents
    /// @param _milestoneIndex Is the index of the milestone object that we want to remove from our list of milestones associated with our specified event
    function removeMilestone(uint256 _eventId, uint256 _milestoneIndex) external onlyEventCreator(_eventId) {
        // Checks to see that the eventId(also an index) is within the bounds of our ongoingEvents array. If the array has a total of just 9 items and you set eventId to 10 then you would be outside the bounds
        require(_eventId < ongoingEvents.length, "Event ID is not valid");
        // Check to see that the index is within the bounds of our list of all the milestones associated with the specified event
        require(_milestoneIndex < eventMilestones[_eventId].length, "Milestone index is not valid.");

        // Remove by swapping the milestone you want to delete with the last milestone and then removing the last one.
        uint lastIndex = eventMilestones[_eventId].length - 1;
        // 	Swap the last item with the index we want to remove
        eventMilestones[_eventId][_milestoneIndex] = eventMilestones[_eventId][lastIndex];
        // 	Remove the last item
        eventMilestones[_eventId].pop();
        // For every donation this function will check if it needs to update this events milestone(s) status' to 'completed' if the target amount was reached
        _updateMilestones(_eventId);
    }

    /// @notice This function is to be used only by the creator of the event to set the status
    /// @dev This feature may also be set to automatically set the status of an event, currently access control is provided to the creator of the event, possibility to add onto this functionality
    /// @param _eventId Is the ID of the event, produced during creation of event or retrieved by getAllEvents() & ongoingEvents
    /// @param _status Is the status of event, 3 Statuses: 0=Active(Default), 1=Cancelled & 2=Successful
    function setEventStatus(uint _eventId, EventStatus _status) external onlyEventCreator(_eventId) {
        CrowdFundingEvent storage chosenEvent = _getEventDetails(_eventId);
        // Sets the status of the event to one of three: Active, Cancelled, Completed
        chosenEvent.Status = _status;
        // Emit the status being changed
        emit EventStatusChanged(_status, chosenEvent.EventCreator, _eventId);
    }

    /// @notice Helper function to check if event exists by its eventId, returns the event object data of specified event
    /// @dev This is a very important function offering flexibility in other fuctions, see: donateToEvent() && setEventStatus() && withdrawContribution()
    /// @return _chosenEvent A single event object containing details about the event defined on creation by creator
    function _getEventDetails(uint256 _eventId) private view returns(CrowdFundingEvent storage _chosenEvent) {
        // Checks to see if the specificed eventId is less than the total events that exist
        require(_eventId < ongoingEvents.length, "Invalid eventId");
        // 	Return the specific event object from the array of all events
        return _chosenEvent = ongoingEvents[_eventId];
    }

    /// @notice Helper function to check if the specified events time has expired
    /// @dev This is used in our getEventStatus() function as a control measure
    /// @param _chosenEvent This is the specified event object passed as a parameter, see: _updateEventStatus() & withdrawContributions()
    /// @return _deadlineReached This returns true if the event is expired or false if it is still ongoing
    function _isEventExpired(CrowdFundingEvent memory _chosenEvent) private view returns(bool) {
        // If the current block.timestamp is more than or equal to the chosen events deadline than the deadline has been reached, return true
        bool deadlineReached = block.timestamp >= _chosenEvent.Deadline;
        return deadlineReached;
    }

    function _isMilestoneCompleted(uint256 _eventId, uint256 _milestoneIndex) private view returns (bool _isTotalAmountRaised) {
        // Get a reference to the milestone
        Milestone storage milestone = eventMilestones[_eventId][_milestoneIndex];
        // Get the total amount raised for the event
        uint256 totalAmountRaised = ongoingEvents[_eventId].totalAmountRaised;
        // Check if the total amount raised is enough to complete the milestone and return if its true or false
        return _isTotalAmountRaised = totalAmountRaised >= milestone.targetAmount;
    }

    /// @notice Helper function to check if the specified events funding goal has been reached
    /// @dev This is used in our _updateEvenStatus() & withdrawContribution() function as a control measure
    /// @param _chosenEvent This is the specified event object passed as a parameter, see: _updateEventStatus() & withdrawContributions()
    /// @return _fundingGoalReached This returns true if the total amount raised by this event exceeds or is equal to the funding goal otherwise it returns false
    function _isFundingGoalReached(CrowdFundingEvent memory _chosenEvent) private pure returns(bool) {
        // If the chosen events total amount raised is greater than or equal to the chsoen events funding goal return true
        bool fundingGoalReached = _chosenEvent.totalAmountRaised >= (_chosenEvent.FundingGoal * 1 ether);
        return fundingGoalReached;
    }

    /// @dev Converts an EventStatus enum value to a corresponding string representation.
    /// @param status The EventStatus value to convert.
    /// @return The string representation of the EventStatus value.
    function _eventStatusToString(EventStatus status) private pure returns (string memory) {
        // If the provided event status is "Active"
        if (status == EventStatus.Active) {
            // Return "Active" as a string
            return "Active";
        // If the provided event status is "Cancelled"
        } else if (status == EventStatus.Cancelled) {
            // Return "Cancelled" as a string
            return "Cancelled";
        // If the provided event status is "Completed"
        } else if (status == EventStatus.Completed) {
            // Return "Completed" as a string
            return "Completed";
        // If the provided event status is none of the above
        } else {
            // Return "Unknown" as a string
            return "Unknown";
        }
    }

    /// @notice Helper function that will update the status of an event automatically for us
    /// @dev This is used in donateToEvent() & withdrawContribution() to automate the provess for us
    /// @param _eventId Is the ID of the event, produced during creation of event or retrieved by getAllEvents() & ongoingEvents
    function _updateEventStatus(uint256 _eventId) private {
        CrowdFundingEvent storage chosenEvent = _getEventDetails(_eventId);
        // Return boolean value after running both functions
        bool eventExpired = _isEventExpired(chosenEvent);
        bool fundingGoalReached = _isFundingGoalReached(chosenEvent);

        // Is the chosenEvent currently Active
        if (chosenEvent.Status == EventStatus.Active) {
            // If yes, then has the current event reached its deadline, is it expired?
            if (eventExpired) {
                // If yes, has the event reached its funding? If yes, set its status to complete else set it to cancelled
                chosenEvent.Status = fundingGoalReached ? EventStatus.Completed : EventStatus.Cancelled;
            // Else if event is currently ongoing then has it reached it funding goal?
            } else if (fundingGoalReached) {
                // If yes, set its status to complete
                chosenEvent.Status = EventStatus.Completed;
            }
        }
    }

    /// @dev Updates the milestones for a given event based on the total amount raised.
    /// @param _eventId The ID of the event
    function _updateMilestones(uint256 _eventId) private {
        // Get the milestones array of the specified event
        Milestone[] storage milestones = eventMilestones[_eventId];
        // Get the total amount raised for the specified event
        uint256 totalAmountRaised = ongoingEvents[_eventId].totalAmountRaised;

        // Loop through all the milestones in the milestones array
        for (uint256 i; i < milestones.length; i++) {
            // Set the previous milestone's target amount to 0 (used in the first iteration)
            uint256 previousMilestoneTarget;
            // Calculate the required amount for the current milestone (convert targetAmount to wei)
            uint256 requiredAmountForCurrentMilestone = milestones[i].targetAmount * 1 ether - previousMilestoneTarget;
            // Calculate the available amount for the current milestone (subtract the previous milestone's target from the total amount raised)
            uint256 availableAmountForCurrentMilestone = totalAmountRaised > previousMilestoneTarget ? totalAmountRaised - previousMilestoneTarget : 0;
            // Determine if the current milestone should be marked as completed
            bool shouldComplete = availableAmountForCurrentMilestone >= requiredAmountForCurrentMilestone;
            // If the current milestone's completed status is different from the shouldComplete value
            if (milestones[i].completed != shouldComplete) {
                // Update the milestone's completed status
                milestones[i].completed = shouldComplete;
                // Emit the MilestoneUpdated event with the updated milestone information
                emit MilestoneUpdated(_eventId, i, shouldComplete);
            }
        }
    }
}