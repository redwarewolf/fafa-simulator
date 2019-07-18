using System.Collections;
using System.Collections.Generic;
using System;
using UnityEngine;

public class Match : MonoBehaviour
{
  private Club myClub;
  private int myClubChance;
  private int myScoreChance;
  private int myStopChance;

  private Club enemyClub;

  private int currentPosition = 50;
  private Club currentBallHolder;

  private int myClubScore;
  private int enemyClubScore;

  static private List<Event> randomEvents;

  public Match(Club amyClub, Club aenemyClub){
    myClub = amyClub;
    enemyClub = aenemyClub;

    myClubChance = (amyClub.midfield()* 100) / (amyClub.midfield() + aenemyClub.midfield());
    myScoreChance = (amyClub.attacking()* 100) / (amyClub.attacking() + aenemyClub.defending() + aenemyClub.goalkeeping());
    myStopChance = ((amyClub.defending() + amyClub.goalkeeping()) * 100) / (amyClub.defending() + amyClub.goalkeeping() + aenemyClub.attacking());

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
    if (currentPosition >= 85 && currentBallHolder == myClub && RandomCalculator.evaluateChances(myScoreChance))
    {
        myClubScore++;

        MatchController.updateMatchScore(myClubScore.ToString() + "-" + enemyClubScore.ToString(), currentBallHolder.getName());
        currentBallHolder = enemyClub;
        currentPosition = 50;
        return true;
    }

    //Si el equipo contrario está en posición de tiro al arco y mete gol

    if (currentPosition <= 15 && currentBallHolder == enemyClub && RandomCalculator.evaluateChances(myStopChance))
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
