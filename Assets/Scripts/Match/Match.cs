using System.Collections;
using System.Collections.Generic;
using System;
using UnityEngine;

public class Match : MonoBehaviour
{
  private Club myClub;
  private int myClubChance;

  private Club enemyClub;

  private int currentPosition = 50;
  private Club currentBallHolder;

  private int myClubScore;
  private int enemyClubScore;

  static private List<Event> randomEvents;

  public Match(Club amyClub, Club aenemyClub){
    myClub = amyClub;
    enemyClub = aenemyClub;

    myClubChance =  (amyClub.ability()* 100) / (amyClub.ability() + aenemyClub.ability());

    Debug.Log(amyClub.getName());
    Debug.Log(aenemyClub.getName());

    }

  public void nextMatchEvent(){


    if(teamScores()){
      return;
    }

    if(RandomCalculator.evaluateChances(myClubChance)){
      currentBallHolder = myClub;
      currentPosition = Math.Min(95, currentPosition+10);
    }
    else{
      currentBallHolder = enemyClub;
      currentPosition = Math.Max(5, currentPosition - 10);
    }

    MatchController.updateMatchUI(currentBallHolder,currentPosition);
  }

  private bool teamScores(){
    //Si estoy en posición de tiro al arco y meto gol
    if (currentPosition == 90 && currentBallHolder == myClub && RandomCalculator.evaluateChances(myClubChance / 4))
    {
        myClubScore++;

        MatchController.updateMatchScore(myClubScore.ToString() + "-" + enemyClubScore.ToString(), currentBallHolder.getName());
        currentBallHolder = enemyClub;
        currentPosition = 50;
        return true;
    }

    //Si el equipo contrario está en posición de tiro al arco y mete gol

    if (currentPosition == 10 && currentBallHolder == enemyClub && RandomCalculator.evaluateChances((100 - myClubChance) / 4))
    {
        enemyClubScore++;

        MatchController.updateMatchScore(myClubScore.ToString() + "-" + enemyClubScore.ToString(), currentBallHolder.getName());
        currentBallHolder = myClub;
        currentPosition = 50;
        return true;
    }
    return false;
  }
}
