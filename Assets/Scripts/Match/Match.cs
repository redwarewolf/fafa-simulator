using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class Match : MonoBehaviour
{
  private Club myClub;
  private Club enemyClub;

  private int currentPosition = 50;

  private int myClubChance;
  private Club currentBallHolder;

  static private List<Event> randomEvents;

  public Match(Club amyClub, Club aenemyClub){
    myClub = amyClub;
    enemyClub = aenemyClub;

    myClubChance =  (amyClub.ability()* 100) / (amyClub.ability() + aenemyClub.ability());
    Debug.Log(amyClub.ability());
    Debug.Log(aenemyClub.ability());

    Debug.Log(myClubChance);
  }

  public void nextMatchEvent(){
    if(RandomCalculator.evaluateChances(myClubChance)){
      currentBallHolder = myClub;
      currentPosition += 10;
    }
    else{
      currentBallHolder = enemyClub;
      currentPosition -= 10;
    }

    Debug.Log("CurrentBallHolder:" + currentBallHolder.getName());
    Debug.Log("CurrentPosition:" + currentPosition.ToString());
    MatchController.updateMatchUI(currentBallHolder,currentPosition);
  }
}
